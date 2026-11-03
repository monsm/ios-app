// HardwareScreen.swift —— 钥匙串 / 硬件台账。
//
// 这屏干什么：列出随身蓝牙钥匙串（ZKBBV1），每台一行三枚读数（电量 / 钥匙数 / 固件），
// 并给出「把本机这把锁的钥匙写进去」与「扫描新钥匙串」两个真动作。
// 钥匙串的价值：不带手机也能开门 —— 它装的是 ekey，不是 App 的账号。
// 数据从哪来：SettingsStore.shared（dongles 台账）+ AppModel.lock（写钥目标是这把锁）。
// 主动作：唯一 signal 填充是「扫描钥匙串」（空态那颗 = EmptyPanel 的出路按钮，有台账时 = 扫描面板那颗）。
import SwiftUI

struct HardwareScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    private var store: SettingsStore { SettingsStore.shared }

    @State private var scanning = false
    @State private var writingId: String?
    /// 2026-11-03：撤销实体钥匙的待确认目标（删了要重新写一遍才能用）。
    @State private var revokeTarget: DongleRecord?
    @State private var busyId: String?
    @State private var keysByDongle: [String: [String]] = [:]
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "钥匙串 / 硬件", tone: tone, status: status)
                if store.dongles.isEmpty {
                    emptyPanel
                } else {
                    ledgerPanel
                    scanPanel
                }
                godPanel
                scopePanel
                if let errorText {
                    VStatusLine(tone: .attention, text: errorText)
                        .padding(.horizontal, V.S.pageGutter)
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("硬件")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("撤销这把锁的钥匙？", isPresented: Binding(
            get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } }
        ), titleVisibility: .visible, presenting: revokeTarget) { d in
            Button("撤销", role: .destructive) { let t = d; revokeTarget = nil; revoke(t) }
            Button("取消", role: .cancel) { revokeTarget = nil }
        } message: { d in
            Text("钥匙串 \(shortMAC(d.mac)) 里那把「\(app.lock?.name ?? "当前锁")」的钥匙会被删掉。以后要用它开门，必须把手机贴近钥匙串重新写一次。")
        }
    }

    // MARK: 页头
    private var tone: Tone {
        if store.dongles.isEmpty { return .neutral }
        // `battery < 0` 是「没读到电量」的哨兵（`SettingsModel.dongles` 用 `?? -1`）——
        // 不排除的话 `-1 < 20` 恒真 ⇒ 页头永远涂成警告色，而其实一台都没读到过电量。
        let low = store.dongles.contains { $0.battery >= 0 && $0.battery < 20 }
        return low ? .attention : .ok
    }

    private var status: String {
        if store.dongles.isEmpty {
            return "没有登记任何钥匙串 · 不带手机开门需要一台"
        }
        let low = store.dongles.filter { $0.battery >= 0 && $0.battery < 20 }.count
        let unbound = store.dongles.filter { !$0.holdsThisLock }.count
        var parts = ["已登记 \(store.dongles.count) 台"]
        if low > 0 { parts.append("低电 \(low) 台") }
        if unbound > 0 { parts.append("未写这把锁 \(unbound) 台") }
        return parts.joined(separator: " · ")
    }

    // MARK: 台账（一台一段读数，不是卡片堆）
    private var ledgerPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "已登记", trailing: store.lastScanAt.map { TimeFormat.ago($0) })
            ForEach(store.dongles) { d in
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapMS) {
                        HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                            Text(d.name)
                                .font(V.F.bodyStrong)
                                .foregroundStyle(V.C.text1)
                            Spacer(minLength: V.S.gapS)
                            VStateDot(
                                tone: d.holdsThisLock ? .ok : .attention,
                                word: d.holdsThisLock ? "已写这把锁" : "未写这把锁"
                            )
                            Text(d.holdsThisLock ? "已写这把锁" : "未写这把锁")
                                .font(V.F.unit)
                                .foregroundStyle(d.holdsThisLock ? V.C.text2 : V.C.warning)
                        }
                        Text(d.mac)
                            .font(V.F.stamp)
                            .foregroundStyle(V.C.text3)
                            .monospacedDigit()
                        SettingRule()
                        VReadingGrid(items: [
                            // 2026-11-01（Round 246）：两个字段都有「未知」哨兵，不能直接拼进字符串：
                            //   · `battery = -1`（没读到电量）⇒ 原来显示「-1 %」并涂警告色；
                            //   · `keys = -1`（没读到钥匙数）⇒ 原来显示「0 把」，与"真的 0 把"分不开。
                            .init(label: "电量", value: d.battery >= 0 ? "\(d.battery)" : "—", unit: d.battery >= 0 ? "%" : "",
                                  tint: d.battery >= 0 && d.battery < 20 ? V.C.warning : V.C.text1),
                            .init(label: "钥匙", value: d.keys >= 0 ? "\(d.keys)" : "—", unit: d.keys >= 0 ? "把" : ""),
                            .init(label: "固件", value: d.firmware),
                        ], columns: 3)
                        .padding(.top, V.S.gapXS)
                        SettingRule()
                        if writingId == d.id {
                            VBusyRow(text: "正在写入 · 钥匙串请贴近手机")
                        } else if busyId == d.id {
                            VBusyRow(text: "正在与钥匙串通信 · 请贴近手机")
                        } else {
                            if d.holdsThisLock {
                                VOutlineButton(title: "撤销这把锁的钥匙", systemImage: "key.slash") {
                                    revokeTarget = d
                                }
                            } else {
                                // 同屏只有一处 signal 填充（扫描面板那颗）。这里的写入是描边动作。
                                VOutlineButton(title: "把「\(app.lock?.name ?? "这把锁")」的钥匙写进去",
                                                systemImage: "key.horizontal") {
                                    write(d)
                                }
                            }
                            HStack(spacing: V.S.gapS) {
                                VOutlineButton(title: "读取状态", systemImage: "arrow.clockwise") {
                                    readState(d)
                                }
                                VOutlineButton(title: "查看已写入的钥匙", systemImage: "list.bullet") {
                                    loadKeys(d)
                                }
                            }
                            VOutlineButton(title: "写入一把未知钥匙（随机 PIN，永久）",
                                           systemImage: "questionmark.key.filled") {
                                writeFault(d)
                            }
                            if let keys = keysByDongle[d.id] {
                                if keys.isEmpty {
                                    Text("这把钥匙串里还没有写入任何锁的钥匙。")
                                        .font(V.F.footnote)
                                        .foregroundStyle(V.C.text3)
                                } else {
                                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                                        ForEach(keys, id: \.self) { mac in
                                            HStack(spacing: V.S.gapS) {
                                                Text(shortMAC(mac))
                                                    .font(V.F.stamp)
                                                    .foregroundStyle(V.C.text1)
                                                    .monospacedDigit()
                                                Spacer(minLength: 0)
                                                Text(DB.keychain(mac).map { LockArchive.displayName($0) } ?? "本机无这把锁的档案")
                                                    .font(V.F.unit)
                                                    .foregroundStyle(DB.keychain(mac) == nil ? V.C.warning : V.C.text3)
                                            }
                                        }
                                    }
                                    .padding(.top, V.S.gapXS)
                                }
                            }
                            SettingRule()
                            VOutlineButton(title: "从本机解绑", systemImage: "minus.circle", tint: V.C.critical) {
                                unbind(d)
                            }
                            Text("解绑只删本机记录，不删钥匙串里已写入的钥匙 —— 那把实体钥匙仍然能开对应锁。")
                                .font(V.F.unit)
                                .foregroundStyle(V.C.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, V.S.pageGutter)
            }
        }
    }

    // MARK: 空态（给出路：扫描 —— 这是这一屏唯一的第一步）
    private var emptyPanel: some View {
        VCard {
            VEmptyState(
                title: "还没有登记钥匙串",
                message: "下一步：把钥匙串拿到手机旁，点「扫描钥匙串」。只认厂商的钥匙串（型号 ZKBBV1），扫描 15 秒，认不到就是没电或没在广播。",
                actionTitle: "扫描钥匙串",
                systemImage: "key.horizontal"
            ) {
                scan()
            }
            .padding(.vertical, V.S.gap24)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 扫描
    /// 2026-11-03（用户实测）：god 入口原来藏在「已写这把锁」的钥匙串行里 ——
    /// 模拟器/新恢复的机器上没有已写入的钥匙串，按钮**永远不出现**。
    /// 现在提为常驻面板：有锁就可用，没锁禁用并说明。
    private var godPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "God 模式")
                Text("锁端全量读数 · 双侧快照 · 凭证变更流水 · 修池（保通信密钥重写 PIN 表）。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VOutlineButton(title: "打开 God 模式", systemImage: "crown.fill") {
                    router.request(.dest(.godMode))
                }
                .disabled(app.currentKeychain == nil)
                if app.currentKeychain == nil {
                    Text("还没有已配对的锁 —— 先添加或恢复一把。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var scanPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "扫描")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    if scanning {
                        VBusyRow(text: "正在扫描 · 15 秒内把钥匙串放在手机旁")
                    } else {
                        VReadingGrid(items: [
                            .init(label: "上次扫描",
                                  value: store.lastScanAt.map { TimeDisplay.clock($0) } ?? "从未"),
                            .init(label: "已登记", value: "\(store.dongles.count)", unit: "台"),
                        ], columns: 2)
                        .padding(.top, V.S.gapXS)
                        SettingRule()
                        VActionButton(title: "扫描钥匙串", systemImage: "dot.radiowaves.left.and.right") {
                            scan()
                        }
                    }
                    SettingsNote(text: "扫描只认 pid 16289 且广播里带 MAC 的设备。扫不到时先确认钥匙串有电（按一下按键看灯），再靠近手机 30 厘米内。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 能力边界（诚实说明这一屏不管什么）
    private var scopePanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "边界")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingsNote(text: "钥匙串是独立硬件：它把某把锁的 ekey 写进去，之后不带手机也能开门。它不等于「手机钥匙」—— 手机钥匙是发给成员手机的，写入对象是账号。")
                    SettingRule()
                    SettingRow(
                        label: "手机钥匙（发给成员）",
                        value: "去签发",
                        tint: V.C.text2,
                        mono: false,
                        symbol: "iphone.gen3",
                        note: "给成员手机签一把开锁钥匙。"
                    ) { router.request(.dest(.mobileKey)) }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: - 动作

    private func scan() {
        guard !scanning else { return }
        scanning = true
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
                // 扫描没找到不算"永久失败"：页面空态仍给下一步，这里只记时刻。
                store.lastScanAt = Int64(Date().timeIntervalSince1970 * 1000)
            }
        }
    }

    private func write(_ d: DongleRecord) {
        guard let kc = app.currentKeychain, writingId == nil else { return }
        writingId = d.id
        errorText = nil
        Task { @MainActor in
            defer { writingId = nil }
            do {
                // 真链路：cmd41 写 ekey（2010~2118 窗口），再 cmd43/44 回读状态与钥匙信息。
                try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc,
                                                               trackId: UInt32.random(in: 1...0x7fff_ffff))
                if let stat = try? await HardwareService.shared.readDongleState(mac: d.mac) {
                    if var rec = DB.dongle(d.mac) { rec.stat = stat; rec.lastKeyLock = kc.mac
                        rec.lastKeyAt = DF.iso().string(from: Date()); DB.saveDongle(rec) }
                }
                // 2026-11-01（Round 265）：原来**成功与失败都没有任何反馈** ——
                // 成功分支只落库、失败分支是个空 `catch`（注释说"已在按钮文案中体现"，实际只停了转圈）。
                // 同页另外五个动作（吊销/读状态/查钥匙/写假钥匙/解绑）都有 errorText 或 toast。
                // 写钥匙是安全相关操作：用户必须知道这把锁的钥匙到底写进去没有。
                AppToast.shared.show("钥匙已写入钥匙串", tone: .ok)
            } catch {
                errorText = "写入失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func revoke(_ d: DongleRecord) {
        // 2026-11-03（全功能点排查）：这一条真删的是**钥匙串里的那把实体钥匙**（cmd41 空 ekey），
        // 而它既没有确认、也没有重入守卫，成功还**一句回执都没有** ——
        // 用户点完看不到任何变化，只会再点一次。逐项补齐。
        guard let kc = app.currentKeychain, writingId == nil else { return }
        writingId = d.id
        errorText = nil
        Task { @MainActor in
            defer { writingId = nil }
            do {
                // 真链路：同一条 cmd41 下发空 ekey 即删除。
                try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
                if var rec = DB.dongle(d.mac) { rec.lastKeyLock = ""; DB.saveDongle(rec) }
                AppToast.shared.show("已从钥匙串里删掉这把锁的钥匙", tone: .ok)
            } catch {
                errorText = "撤销失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 手动读状态（cmd43）：旧实现只在写钥后自动调一次，用户想单独看电量/钥匙数没有入口。
    private func readState(_ d: DongleRecord) {
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

    /// 查看这把钥匙串里存了哪些锁的钥匙（cmd44）。
    private func loadKeys(_ d: DongleRecord) {
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
        guard let kc = app.currentKeychain, busyId == nil else { return }
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
        DB.removeDongle(d.mac)
        keysByDongle[d.id] = nil
        AppToast.shared.show("已从本机解绑（钥匙串里的钥匙不受影响）", tone: .ok)
    }

    private func shortMAC(_ m: String) -> String {
        let h = DB.normalizeMac(m)
        guard h.count == 12 else { return m }
        return String(h.suffix(6)).uppercased()
    }
}
