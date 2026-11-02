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
    @State private var busyId: String?
    @State private var keysByDongle: [String: [String]] = [:]
    @State private var errorText: String?

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 List。
        // 台账每台一行（.swipeActions 提供「解绑」）；扫描/边界是卡片 → cardRow()（.plain 无系统留白）；
        // 页头与错误提示条是整宽内容 → headerRow()。
        List {
            SettingsHeader(title: "钥匙串 / 硬件", tone: tone, status: status).headerRow()
            if store.dongles.isEmpty {
                emptyPanel.cardRow()
                scanPanel.cardRow()
            } else {
                ledgerSection
                scanPanel.cardRow()
            }
            scopePanel.cardRow()
            if let errorText {
                VStatusLine(tone: .attention, text: errorText).headerRow()   // 提示条不是卡片
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gap16, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("硬件")
        .navigationBarTitleDisplayMode(.inline)
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
    /// 一台钥匙串 = 一行：名称 + MAC + 三枚读数，动作收成「1 主 + 1 Menu」。
    /// 原来同屏 5 个描边按钮（撤销/写入/读取/查看/写随机钥 + 解绑），违反 ui-glass 的克制原则。
    /// 解绑是破坏性动作，移进 .swipeActions（系统给红色背景，且不会误触）。
    private var ledgerSection: some View {
        Section {
            ForEach(store.dongles) { d in
                dongleRow(d)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { unbind(d) } label: {
                            Label("从本机解绑", systemImage: "minus.circle")
                        }
                    }
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("已登记")
                Spacer(minLength: 0)
                if let at = store.lastScanAt {
                    Text(TimeFormat.ago(at))
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                }
            }
        } footer: {
            // 解绑移进 swipeActions 后，必须有一处**常驻可见**的说明 ——
            // 只写在一行卡片的末句里，用户滑不动仍然找不到。
            Text("向左滑动这一行可以解绑")
        }
    }

    @ViewBuilder
    private func dongleRow(_ d: DongleRecord) -> some View {
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
            Text(shortMAC(d.mac))
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
                // 1 主 + 1 Menu：主按钮是这台钥匙串上最常做的那件事，其余全部收进 Menu。
                HStack(spacing: V.S.gapS) {
                    if d.holdsThisLock {
                        VOutlineButton(title: "读取状态", systemImage: "arrow.clockwise") {
                            readState(d)
                        }
                    } else {
                        // 同屏只有一处 signal 填充（扫描面板那颗）。这里的写入是描边动作。
                        VOutlineButton(title: "把「\(app.lock?.name ?? "这把锁")」的钥匙写进去",
                                        systemImage: "key.horizontal") {
                            write(d)
                        }
                    }
                    dongleMenu(d)
                }
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
            Text("解绑只删本机记录，不删钥匙串里已写入的钥匙 —— 那把实体钥匙仍然能开对应锁。")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, V.S.gapXS)
    }

    /// 次要动作收进系统 Menu（撤销 / 查看 / 写随机钥），避免同屏 5 个玻璃按钮。
    private func dongleMenu(_ d: DongleRecord) -> some View {
        Menu {
            Button {
                loadKeys(d)
            } label: {
                Label("查看已写入的钥匙", systemImage: "list.bullet")
            }
            Button {
                writeFault(d)
            } label: {
                Label("写入一把未知钥匙（随机 PIN，永久）", systemImage: "questionmark.key.filled")
            }
            if d.holdsThisLock {
                Divider()
                Button(role: .destructive) {
                    revoke(d)
                } label: {
                    Label("撤销这把锁的钥匙", systemImage: "key.slash")
                }
            }
        } label: {
            // 这里的空闭包是**有意的**：它是 Menu 的 label，点击由外层 Menu 接管，
            // 按钮自己的 action 永远不会被调用（配合下面的 allowsHitTesting(false)）。
            // 复用 VOutlineButton 是为了与页面上其它次级按钮同一套外观，而不是再造一个样式。
            VOutlineButton(title: "更多", systemImage: "ellipsis.circle") {}
                .allowsHitTesting(false)
        }
        .accessibilityLabel("更多动作")
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
    }

    // MARK: 扫描
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
        }
    }

    // MARK: - 动作

    private func scan() {
        guard !scanning else { return }
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
                errorText = nil
            } catch {
                store.lastScanAt = Int64(Date().timeIntervalSince1970 * 1000)
                // 2026-11-02（P0 修复）：原来这个 catch 只记时刻，失败被整个吞掉 ——
                // 界面反而显示「上次扫描 · 刚刚」，用户以为"扫过一轮、没有设备"，
                // 而真实原因可能是蓝牙没开/权限被拒。现在把两种结果分开说：
                //   · 扫到 0 台（scanForDongle 的超时）是正常空结果，给出可执行的下一步；
                //   · 扫描出错原样报错。
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if msg.contains("超时") {
                    errorText = "扫描完成：15 秒内没有发现钥匙串（0 台）。先按一下钥匙串按键看灯确认有电，再把它放在手机 30 厘米内重试。"
                } else {
                    errorText = "扫描失败：" + msg
                }
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
        guard let kc = app.currentKeychain else { return }
        Task { @MainActor in
            do {
                // 真链路：同一条 cmd41 下发空 ekey 即删除。
                try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
                if var rec = DB.dongle(d.mac) { rec.lastKeyLock = ""; DB.saveDongle(rec) }
                // P1 修复：撤销成功原来没有任何反馈，而且 dongles 只依赖 SettingsStore.revision，
                // 不 bump 的话整行读数不会重绘 —— 用户点了撤销，界面什么都不变。
                SettingsStore.shared.notifyChanged()
                AppToast.shared.show("已撤销这把锁的钥匙", tone: .ok)
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
