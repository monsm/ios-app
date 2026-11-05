// HardwareHomeScreen.swift —— 钥匙串 / 硬件（V8 设计语言）
//
// 与 HardwareScreen 的能力对齐：列出随身蓝牙钥匙串（ZKBBV1），每台三枚读数（电量 / 钥匙数 / 固件），
// 并保留全部真动作：扫描钥匙串、把本机这把锁的钥匙写进去、读取状态、查看已写入的钥匙、
// 写入一把未知钥匙、撤销这把锁的钥匙、从本机解绑。
// 只改渲染层：落盘仍走 DB.saveDongle / DB.removeDongle，键仍是 kf_keychain_dongles。
//
// 与旧页的刻意差异：
//   ① 空壳模式整页只读：旧页的台账读 DB.dongles()（空壳返回空集），但「扫描」仍会把真设备写进
//      真实台账 —— 空壳里必须连写入口一起停。
//   ② 只读试验模式把话说在前面：硬件服务里的读状态与查钥匙也不在只读放行表，点了会被拦；
//      先说明白，不让用户点了才发现。
import SwiftUI

struct HardwareHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    private var store: SettingsStore { SettingsStore.shared }

    @State private var scanning = false
    @State private var writingId: String?
    /// 撤销实体钥匙的待确认目标（删了要重新写一遍才能用）。
    @State private var revokeTarget: DongleRecord?
    @State private var busyId: String?
    @State private var keysByDongle: [String: [String]] = [:]
    @State private var errorText: String?

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }
    private var dongles: [DongleRecord] { store.dongles }

    private var lowCount: Int { dongles.filter { $0.battery >= 0 && $0.battery < 20 }.count }
    private var unboundCount: Int { dongles.filter { !$0.holdsThisLock }.count }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示钥匙串" }
        if dongles.isEmpty { return "还没有登记钥匙串" }
        var parts = ["已登记 \(dongles.count) 台"]
        if lowCount > 0 { parts.append("低电 \(lowCount) 台") }
        if unboundCount > 0 { parts.append("未写这把锁 \(unboundCount) 台") }
        return parts.joined(separator: " · ")
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏数据，不改动数据。钥匙串台账不显示，也不提供扫描、写入与解绑。" }
        return "钥匙串是独立硬件：它把某把锁的钥匙写进去，之后不带手机也能开门。它装的是钥匙，不是 App 的账号。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if dongles.isEmpty {
                VEmpty(
                    title: "先添加门锁",
                    reason: "下一步：把钥匙串拿到手机旁，点「扫描钥匙串」。只认厂商的钥匙串（型号 ZKBBV1），扫描 15 秒，认不到就是没电或没在广播。",
                    actionTitle: "扫描钥匙串"
                ) { scan() }
                scanCard
                godCard
                scopeCard
                errorCard
            } else {
                ledgerCard
                scanCard
                godCard
                scopeCard
                errorCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .v8Confirm(
            isPresented: Binding(
                get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } }
            ),
            title: "撤销这把锁的钥匙？",
            consequence: "钥匙串 \(revokeTarget.map { DB.shortMac($0.mac) } ?? "") 里那把「\(app.lock?.name ?? "当前锁")」的钥匙会被删掉。以后要用它开门，必须把手机贴近钥匙串重新写一次 —— 这个动作不能撤销。",
            confirmTitle: "撤销",
            isDestructive: true
        ) {
            if let d = revokeTarget {
                revokeTarget = nil
                revoke(d)
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("key.horizontal"), label: "钥匙串", value: "\(dongles.count) 台")
                VChip2(icon: .ring(dongles.isEmpty ? 0.02 : 1, lowCount == 0 ? V8.C.ok : V8.C.warn),
                       label: "低电", value: lowCount == 0 ? "没有" : "\(lowCount) 台")
                VChip2(icon: .ring(dongles.isEmpty ? 0.02 : 1, unboundCount == 0 ? V8.C.ok : V8.C.warn),
                       label: "未写这把锁", value: unboundCount == 0 ? "没有" : "\(unboundCount) 台")
                VChip2(icon: .glyph("clock"), label: "上次扫描",
                       value: store.lastScanAt.map { TimeFormat.ago($0) } ?? "从未")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 台账

    private var ledgerCard: some View {
        VCard2 {
            VCardHead(eyebrow: "已登记", statement: "一行一台", trailing: "\(dongles.count) 台")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(dongles.enumerated()), id: \.element.id) { pair in
                    if pair.offset > 0 {
                        VDivider2()
                            .padding(.vertical, V8.S.gapM)
                    }
                    dongleBlock(pair.element)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func dongleBlock(_ d: DongleRecord) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            HStack(spacing: V8.S.gapS) {
                Text(d.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Text(d.holdsThisLock ? "已写这把锁" : "未写这把锁")
                    .font(V8.T.caption)
                    .foregroundStyle(d.holdsThisLock ? V8.C.ok : V8.C.warn)
                Spacer(minLength: 0)
            }
            Text(d.mac)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .monospacedDigit()
            VStack(spacing: 0) {
                VDataRow(tag: "电量", tagTint: d.battery >= 0 && d.battery < 20 ? V8.C.warn : V8.C.ink4,
                         title: "电池剩余", value: d.battery >= 0 ? "\(d.battery)" : "—",
                         unit: d.battery >= 0 ? "%" : nil)
                VDotRule()
                VDataRow(tag: "钥匙", tagTint: V8.C.ink4, title: "已写钥匙数",
                         value: d.keys >= 0 ? "\(d.keys)" : "—", unit: d.keys >= 0 ? "把" : nil)
                VDotRule()
                VDataRow(tag: "固件", tagTint: V8.C.ink4, title: "固件版本", value: d.firmware)
            }
            .padding(.top, V8.S.gapXS)
            actionArea(d)
        }
        .frame(minHeight: V8.H.min)
    }

    @ViewBuilder
    private func actionArea(_ d: DongleRecord) -> some View {
        if writingId == d.id {
            VBusy(text: "正在写入 · 钥匙串请贴近手机")
        } else if busyId == d.id {
            VBusy(text: "正在与钥匙串通信 · 请贴近手机")
        } else {
            if d.holdsThisLock {
                Button { revokeTarget = d } label: {
                    actionLabel("撤销这把锁的钥匙", tint: V8.C.danger)
                }
                .buttonStyle(.plain)
                .disabled(readOnly)
                .opacity(readOnly ? 0.45 : 1)
            } else {
                Button { write(d) } label: {
                    actionLabel("把「\(app.lock?.name ?? "这把锁")」的钥匙写进去", tint: V8.C.accent)
                }
                .buttonStyle(.plain)
                .disabled(readOnly)
                .opacity(readOnly ? 0.45 : 1)
            }
            HStack(spacing: V8.S.gapL) {
                Button { readState(d) } label: {
                    Text("读取状态")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
                Button { loadKeys(d) } label: {
                    Text("查看已写入的钥匙")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Button { writeFault(d) } label: {
                actionLabel("写入一把未知钥匙（随机 PIN，永久）", tint: V8.C.ink3)
            }
            .buttonStyle(.plain)
            .disabled(readOnly)
            .opacity(readOnly ? 0.45 : 1)
            if let keys = keysByDongle[d.id] {
                if keys.isEmpty {
                    Text("这把钥匙串里还没有写入任何锁的钥匙。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapXS)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        ForEach(keys, id: \.self) { mac in
                            HStack(spacing: V8.S.gapS) {
                                Text(DB.shortMac(mac))
                                    .font(V8.T.caption)
                                    .foregroundStyle(V8.C.ink1)
                                    .monospacedDigit()
                                Spacer(minLength: 0)
                                Text(DB.keychain(mac).map { LockArchive.displayName($0) } ?? "本机无这把锁的档案")
                                    .font(V8.T.caption)
                                    .foregroundStyle(DB.keychain(mac) == nil ? V8.C.warn : V8.C.ink4)
                            }
                        }
                    }
                    .padding(.top, V8.S.gapXS)
                }
            }
            Button { unbind(d) } label: {
                actionLabel("从本机解绑", tint: V8.C.danger)
            }
            .buttonStyle(.plain)
            .disabled(readOnly)
            .opacity(readOnly ? 0.45 : 1)
            Text("解绑只删本机记录，不删钥匙串里已写入的钥匙 —— 那把实体钥匙仍然能开对应锁。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapXS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionLabel(_ title: String, tint: Color) -> some View {
        HStack(spacing: V8.S.gapS) {
            Text(title)
                .font(V8.T.caption)
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(V8.T.micro)
                .foregroundStyle(V8.C.ink4)
                .accessibilityHidden(true)
        }
        .frame(minHeight: V8.H.min)
        .contentShape(Rectangle())
    }

    // MARK: - 扫描

    private var scanCard: some View {
        VCard2 {
            VCardHead(eyebrow: "扫描", statement: scanning ? "正在扫描 · 15 秒内把钥匙串放在手机旁" : "只认厂商的钥匙串", trailing: "15 秒")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "上次扫描", value: store.lastScanAt.map { TimeDisplay.clock($0) } ?? "从未"),
                .init(label: "已登记", value: "\(dongles.count)", unit: "台")
            ])
            .padding(.top, V8.S.gapM)
            if scanning {
                VBusy(text: "正在扫描 · 15 秒内把钥匙串放在手机旁")
                    .padding(.top, V8.S.gapM)
            } else {
                Button { scan() } label: {
                    Text("扫描钥匙串")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, V8.S.gapM)
            }
            Text("扫描只认 pid 16289 且广播里带 MAC 的设备。扫不到时先确认钥匙串有电（按一下按键看灯），再靠近手机 30 厘米内。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if readOnly {
                Text(TrialCopy.blocked("除扫描外的钥匙串读写命令", note: "读状态与查钥匙也在内"))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - God 模式入口

    private var godCard: some View {
        VCard2 {
            VCardHead(eyebrow: "God 模式", statement: app.currentKeychain == nil ? "先添加一把锁" : "锁端全量读数与凭证对账")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("锁端全量读数 · 凭证台账对账 · 变更流水 · 修池（保通信密钥重写 PIN 表）。诊断项都收在「诊断」页里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "打开 God 模式",
                    detail: app.currentKeychain == nil ? "还没有已配对的锁 —— 先添加或恢复一把" : "读数 / 台账 / 变更 / 修池") {
                router.request(.dest(.godMode))
            }
            .disabled(app.currentKeychain == nil)
            .opacity(app.currentKeychain == nil ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 能力边界

    private var scopeCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "边界", statement: "钥匙串不等于手机钥匙")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("钥匙串是独立硬件：它把某把锁的钥匙写进去，之后不带手机也能开门。它不等于「手机钥匙」—— 手机钥匙是发给成员手机的，写入对象是账号。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "手机钥匙（发给成员）", detail: "给成员手机签一把开锁钥匙") {
                router.request(.dest(.mobileKey))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "钥匙串", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，钥匙串台账不显示，也不提供扫描、写入与解绑 —— 扫描会把真设备写进真实台账，写入会改真实硬件记录。")
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

    // MARK: - 失败态

    @ViewBuilder
    private var errorCard: some View {
        if let errorText {
            VFailure(
                what: "钥匙串操作没有完成",
                why: errorText,
                next: "确认钥匙串有电（按一下按键看灯）、靠近手机 30 厘米内，再重试。"
            )
        }
    }

    // MARK: - 动作

    private func scan() {
        guard !scanning else { return }
        guard !decoyed else {
            errorText = "空壳模式下不扫描、不登记钥匙串 —— 先退出空壳。"
            return
        }
        scanning = true
        errorText = nil
        Task { @MainActor in
            defer { scanning = false }
            do {
                // 真链路：全扫 15s，只认 pid 16289 且广播带 MAC，落 kf_keychain_dongles。
                let d = try await HardwareService.shared.scanForDongle()
                var rec = DB.dongle(d.mac) ?? Dongle(mac: d.mac, name: d.name)
                if rec.boundAt.isEmpty { rec.boundAt = DF.iso().string(from: Date()) }
                rec.lastSeenAt = DF.iso().string(from: Date())
                DB.saveDongle(rec)
                store.lastScanAt = Int64(Date().timeIntervalSince1970 * 1000)
            } catch {
                errorText = "扫描失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func write(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不写入钥匙串台账 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("写钥匙")
            return
        }
        guard writingId == nil else { return }
        guard let kc = app.currentKeychain else {
            errorText = "还没有当前锁 —— 写进去的钥匙要对应一把锁。先在「门」页选中一把锁，再来写。"
            return
        }
        writingId = d.id
        errorText = nil
        Task { @MainActor in
            defer { writingId = nil }
            do {
                // 真链路：写 ekey，再回读状态与钥匙信息。
                try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc,
                                                               trackId: UInt32.random(in: 1...0x7fff_ffff))
                if let stat = try? await HardwareService.shared.readDongleState(mac: d.mac) {
                    if var rec = DB.dongle(d.mac) { rec.stat = stat; rec.lastKeyLock = kc.mac
                        rec.lastKeyAt = DF.iso().string(from: Date()); DB.saveDongle(rec) }
                }
                AppToast.shared.show("钥匙已写入钥匙串", tone: .ok)
            } catch {
                errorText = "写入失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func revoke(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不改动钥匙串台账 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("撤销")
            return
        }
        guard let kc = app.currentKeychain, writingId == nil else { return }
        writingId = d.id
        errorText = nil
        Task { @MainActor in
            defer { writingId = nil }
            do {
                // 真链路：同一条写钥命令下发空 ekey 即删除。
                try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
                if var rec = DB.dongle(d.mac) { rec.lastKeyLock = ""; DB.saveDongle(rec) }
                AppToast.shared.show("已从钥匙串里删掉这把锁的钥匙", tone: .ok)
            } catch {
                errorText = "撤销失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 手动读状态：旧实现只在写钥后自动调一次，用户想单独看电量 / 钥匙数没有入口。
    private func readState(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不读取钥匙串 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("读状态命令")
            return
        }
        guard busyId == nil else { return }
        busyId = d.id
        errorText = nil
        Task { @MainActor in
            defer { busyId = nil }
            do {
                let stat = try await HardwareService.shared.readDongleState(mac: d.mac)
                if var rec = DB.dongle(d.mac) { rec.stat = stat; DB.saveDongle(rec) }
                AppToast.shared.show("状态已更新", tone: .ok)
            } catch {
                errorText = "读状态失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 查看这把钥匙串里存了哪些锁的钥匙。
    private func loadKeys(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不读取钥匙串台账 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("查钥匙命令")
            return
        }
        guard busyId == nil else { return }
        busyId = d.id
        errorText = nil
        Task { @MainActor in
            defer { busyId = nil }
            do {
                keysByDongle[d.id] = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            } catch {
                errorText = "查钥匙失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 写入未知/假钥匙：随机 PIN、永久、不绑成员 —— 它开不了锁，只验证钥匙串本身能收钥。
    private func writeFault(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不写入钥匙串 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("写未知钥匙")
            return
        }
        guard busyId == nil else { return }
        guard let kc = app.currentKeychain else {
            errorText = "还没有当前锁 —— 未知钥匙也要按某把锁的身份写入。先在「门」页选中一把锁。"
            return
        }
        busyId = d.id
        errorText = nil
        Task { @MainActor in
            defer { busyId = nil }
            do {
                try await HardwareService.shared.writeFaultDongleKey(dongleMac: d.mac, lock: kc)
                AppToast.shared.show("未知钥匙已写入（随机 PIN，开不了锁）", tone: .ok)
            } catch {
                errorText = "写假钥匙失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 从本机解绑：只删本机台账，不动实体钥匙里已写入的钥匙。
    private func unbind(_ d: DongleRecord) {
        guard !decoyed else {
            errorText = "空壳模式下不改动本机台账 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            errorText = TrialCopy.blocked("解绑")
            return
        }
        DB.removeDongle(d.mac)
        keysByDongle[d.id] = nil
        AppToast.shared.show("已从本机解绑（钥匙串里的钥匙不受影响）", tone: .ok)
    }
}
