// 蓝牙钥匙串（ZKBBV1 pid=16289）—— 随身硬件钥匙管理页
//
// 2026-10-28 新建：这一整套能力**服务层 100% 就绪、UI 0%** ——
//   · 数据层 `Dongle` / `DongleStat` + `DB.dongles/dongle/saveDongle/removeDongle`
//   · 服务层 `scanForDongle` / `readDongleState` / `writeDongleKey` / `deleteDongleKey` / `dongleKeys`
//   · 备份层 BackupKit / BackupStudioKit 都含 keychainDongles
//   · 但全仓**零 UI 入口**，而 `MobileKeyView.swift:71` 的文案还在对用户说
//     「与「蓝牙钥匙串」不同：钥匙串是随身硬件（走 41/43/44）」—— 用户会去找，找不到。
//
// APK 对应 page-addblekey 的 8 个按钮：scanKC / addKeyChain / addFaultKeyChain /
// delKeyChain / getEKeyInfo / getNowEKeyInfo / getStatus / addOtherKeyChain。
import SwiftUI

struct DongleView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var scanning = false
    @State private var error = ""
    @State private var tick = 0

    /// 选中的目标锁（写钥/删钥的对象）。
    @State private var targetLockMac: String = ""
    /// 已查到的钥匙 MAC 列表（按钥匙串 mac）。
    @State private var keysByDongle: [String: [String]] = [:]

    var body: some View { vkBody.destined(.dongle) }

    var vkBody: some View {
        Form {
            scanSection
            if !error.isEmpty {
                Section {
                    Text(error)
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("操作失败：\(error)")
                }
            }
            if DB.dongles().isEmpty {
                Section {
                    EmptyState(systemImage: "key.horizontal",
                               title: "还没有绑定蓝牙钥匙串",
                               message: "钥匙串是随身硬件：把它靠近手机，点上面的「搜索钥匙串」绑定。",
                               actionTitle: "搜索钥匙串") { Task { await scan() } }
                }
            } else {
                ForEach(DB.dongles()) { d in
                    dongleSection(d)
                }
            }
            Section {
                Text("蓝牙钥匙串 = 能独立开锁的随身硬件（ZKBBV1）。它和「手机钥匙」不同："
                     + "手机钥匙是把 ekey 发给成员的手机，钥匙串是把 ekey 写进一个实体。"
                     + "两者都从同一把锁的 PIN 池签发，互不影响。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("这是什么")
            }
        }
        .navigationTitle("蓝牙钥匙串")
        .variantList()
        .dsScreenBackground()
        .id(tick)
    }

    // MARK: - 扫描

    private var scanSection: some View {
        Section {
            BusyButton(title: scanning ? "正在搜索…" : "搜索钥匙串",
                       systemImage: "dot.radiowaves.left.and.right",
                       isBusy: scanning) {
                Task { await scan() }
            }
            .disabled(scanning)
        } header: {
            Text("搜索")
        } footer: {
            Text("搜索需要钥匙串在身边并已开机（指示灯闪）。已绑定的钥匙串会直接列出，不必重扫。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    private func scan() async {
        guard !scanning else { return }
        scanning = true
        error = ""
        defer { scanning = false }
        do {
            let d = try await HardwareService.shared.scanForDongle()
            app.showToast("已找到钥匙串「\(d.name.isEmpty ? d.mac : d.name)」")
            tick += 1
        } catch {
            self.error = "搜索失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 单把钥匙串

    @ViewBuilder
    private func dongleSection(_ d: Dongle) -> some View {
        Section {
            // 头部信息
            HStack(spacing: DS.Space.s) {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(DS.Palette.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name.isEmpty ? "未命名钥匙串" : d.name)
                        .vkFont(.subheadline, weight: .medium)
                    Text(shortMAC(d.mac))
                        .vkFont(.caption2.monospaced())
                        .foregroundStyle(DS.Palette.textSub)
                }
                Spacer(minLength: 0)
                if let st = d.stat {
                    Text(st.power >= 0 ? "\(st.power)%" : "电量未读")
                        .vkFont(.caption)
                        .foregroundStyle(st.power >= 0 && st.power <= 20 ? DS.Palette.danger : DS.Palette.textSub)
                }
            }
            .frame(minHeight: DS.Hit.min)

            if let st = d.stat {
                LabeledRow("电量", st.power >= 0 ? "\(st.power)%" : "未读")
                LabeledRow("钥匙", st.ekeyCount >= 0 && st.ekeyAmount >= 0
                           ? "\(st.ekeyCount) / \(st.ekeyAmount)" : "未读")
                LabeledRow("固件", st.firmware.isEmpty ? "未读" : st.firmware)
                LabeledRow("型号", st.pid == 0 ? "未读" : PidMap.modelName(st.pid))
            }
            LabeledRow("最后见到", d.lastSeenAt.isEmpty ? "—" : shortTime(d.lastSeenAt))

            // 读状态
            BusyButton(title: "读取状态", systemImage: "arrow.clockwise", isBusy: busy) {
                Task { await readState(d) }
            }
            .disabled(busy)

            // 查这把钥匙串里存了哪些锁的钥匙
            Button {
                Task { await loadKeys(d) }
            } label: {
                Label("查看已写入的钥匙", systemImage: "list.bullet")
            }
            .disabled(busy)
            if let keys = keysByDongle[d.mac] {
                if keys.isEmpty {
                    Text("这把钥匙串里还没有写入任何锁的钥匙。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(keys, id: \.self) { m in
                        HStack(spacing: DS.Space.s) {
                            Text(shortMAC(m)).vkFont(.caption.monospaced())
                            Spacer(minLength: 0)
                            if let kc = DB.keychain(DB.normalizeMac(m)) {
                                Text(LockArchive.displayName(kc))
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                            } else {
                                Text("本机无这把锁的档案")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.warn)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(d.name.isEmpty ? "钥匙串" : d.name)
        } footer: {
            if !d.lastKeyLock.isEmpty {
                Text("最近一次写钥：\(shortMAC(d.lastKeyLock)) · \(shortTime(d.lastKeyAt))")
                    .vkFont(.caption2)
            }
        }

        // 写钥 / 删钥
        Section {
            if app.devices.isEmpty {
                Text("本机还没有门锁档案 —— 先添加一把锁，才能给它写钥匙。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            } else {
                Picker("目标门锁", selection: $targetLockMac) {
                    Text("请选择").tag("")
                    ForEach(app.devices) { kc in
                        Text(LockArchive.displayName(kc)).tag(kc.mac)
                    }
                }
                Button {
                    Task { await writeKey(d) }
                } label: {
                    Label("把钥匙写入这把锁", systemImage: "square.and.arrow.down")
                }
                .disabled(busy || targetLockMac.isEmpty)
                // 「添加假钥匙」= 随机 pin、不绑成员（APK addFaultKeyChain）。
                // 用途：给访客/临时工一把能开门但查不到归属的实体钥匙，或用来验证钥匙串本身可用。
                Button {
                    Task { await writeFaultKey(d) }
                } label: {
                    Label("写入一把假钥匙（随机 PIN）", systemImage: "questionmark.key.filled")
                }
                .disabled(busy)
                Button(role: .destructive) {
                    Task { await removeKey(d) }
                } label: {
                    Label("从钥匙串删除这把锁的钥匙", systemImage: "trash")
                }
                .disabled(busy || targetLockMac.isEmpty)
            }
        } header: {
            Text("写钥 / 删钥")
        } footer: {
            Text("写钥会把该锁的 ekey 写进这把实体钥匙串（走 cmd 41）。"
                 + "⚠「假钥匙」用随机 PIN、不绑成员 —— 它**开不了锁**（PIN 不在锁的 PIN 池里），"
                 + "只用来验证钥匙串本身能收钥，或给不该真正通行的人一把看着像的钥匙。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
        }

        // 解绑
        Section {
            Button(role: .destructive) {
                DB.removeDongle(d.mac)
                app.showToast("已从本机解绑（钥匙串里的钥匙不受影响）")
                tick += 1
            } label: {
                Label("从本机解绑", systemImage: "minus.circle")
            }
        } footer: {
            Text("解绑只删本机记录，不删钥匙串里已写入的钥匙 —— 那把实体钥匙仍然能开对应锁。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
        }
    }

    // MARK: - 操作

    private func readState(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            _ = try await HardwareService.shared.readDongleState(mac: d.mac)
            app.showToast("状态已更新")
            tick += 1
        } catch {
            self.error = "读状态失败: \(error.localizedDescription)"
        }
    }

    private func loadKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            let keys = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            keysByDongle[d.mac] = keys
            tick += 1
        } catch {
            self.error = "查钥匙失败: \(error.localizedDescription)"
        }
    }

    private func writeKey(_ d: Dongle) async {
        guard !busy, let kc = app.devices.first(where: { $0.mac == targetLockMac }) else { return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc,
                                                           trackId: KeyGen.genTrackId())
            app.showToast("钥匙已写入「\(LockArchive.displayName(kc))」")
            tick += 1
        } catch {
            self.error = "写钥失败: \(error.localizedDescription)"
        }
    }

    private func writeFaultKey(_ d: Dongle) async {
        guard !busy, let kc = app.devices.first(where: { $0.mac == targetLockMac }) else {
            error = "请先选一把目标门锁"
            return
        }
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await HardwareService.shared.writeFaultDongleKey(dongleMac: d.mac, lock: kc)
            app.showToast("假钥匙已写入（随机 PIN，不绑成员）")
            tick += 1
        } catch {
            self.error = "写假钥匙失败: \(error.localizedDescription)"
        }
    }

    private func removeKey(_ d: Dongle) async {
        guard !busy, let kc = app.devices.first(where: { $0.mac == targetLockMac }) else { return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            app.showToast("已从钥匙串删除「\(LockArchive.displayName(kc))」的钥匙")
            tick += 1
        } catch {
            self.error = "删钥失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 格式化

    private func shortMAC(_ m: String) -> String {
        let h = m.replacingOccurrences(of: ":", with: "").lowercased()
        guard h.count == 12 else { return m }
        return String(h.suffix(6)).uppercased()
    }

    private func shortTime(_ s: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: s) else { return s }
        let f = DateFormatter()
        // 2026-10-28：本仓规范 —— 日期格式必须钉 locale 与公历，
        // 否则非公历系统下 MM-dd 会算出异 era 年份。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}
