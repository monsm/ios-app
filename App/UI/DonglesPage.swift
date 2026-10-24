//
//  DonglesPage.swift
//  蓝牙钥匙串 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 每枚钥匙串是一张"硬件名片"
//  ═══════════════════════════════════════════════════════════
//
//  旧版: List + 三行文字 + 三个 MetricTile 挤在行内 + 长按菜单
//
//  新版:
//    · 每枚钥匙串一张卡: 顶部 56pt 钥匙图标 (已配钥匙时铜色发光)
//    · 电量做一条 4pt 横条 (低电橙/危险红), 不是纯数字
//    · 钥匙存量用 "3 / 8" 形式, 两侧独立缺失时显示 "—"
//    · 动作全部收进行的 Menu (读状态/写钥匙/查钥匙/删钥匙)
//    · 空态: 一大枚钥匙轮廓 + 引导
//

import SwiftUI

/// 蓝牙钥匙串页
struct DonglesPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var dongles: [Dongle] = []
    @State private var busy = false

    var body: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("蓝牙钥匙串", subtitle: "随身开门的实体钥匙串") {
                headerCard.xScrollLift()

                if app.current == nil {
                    noLockBanner.xScrollLift()
                }

                if dongles.isEmpty {
                    emptyState.xScrollLift()
                } else {
                    ForEach(dongles) { d in
                        dongleCard(d)
                    }
                }
        }
        }
        .task { reload() }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 头部
    // ═══════════════════════════════════════════════════════

    private var headerCard: some View {
        XPanel(kind: .hero) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.m) {
                    // 规范 §10「圆形底」：只允许 StatChip 图标 34pt、列表图标 20pt，**其余不加底**。
                    // 这里原来是 56pt 的洗染圆底 —— 既不是 34 也不是 20，是我按感觉加的。
                    // 去掉底之后图标直接落在 hero 渐变上：hero 卡本身就是「媒体」，不需要再垫一层。
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: XIcon.lg, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("随身开门")
                            .xFont(.headline)
                            .foregroundStyle(XPalette.text)
                        Text("钥匙串靠近门锁即可开门, 不用掏手机")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // 六图改造 (2026-10-23): 加**图 5 的 44px 读数**（已配对 N 把）。
                //
                // 图 5 的卡先给一个量，再给动作。之前这张 hero 只有一句标语 + 一个按钮 ——
                // 用户不知道自己有没有配对过、配了几把。数量 + 环把"当前状态"补上了。
                let pairedN = dongles.count
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        XHeroNumber(text: String(pairedN), color: XPalette.accentText,
                                    unit: "把已配对")
                        Text(pairedN == 0 ? "还没配对 —— 上电后点下面搜索" : "靠近门锁即可开门")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 66,
                        progress: pairedN == 0 ? 0.02 : min(1, Double(pairedN) / 3),
                        widthRatio: 0.14,
                        showsCursor: false,
                        showsTick: false
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }

                XBusyButton(title: busy ? "搜索中…" : "搜索钥匙串",
                            systemImage: "antenna.radiowaves.left.and.right",
                            busy: busy, style: .primary) {
                    Task { await scan() }
                }
                .disabled(busy)
            }
        }
    }

    private var noLockBanner: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XIcon.sm, weight: .semibold))
                .foregroundStyle(XPalette.warn)
                .accessibilityHidden(true)
            Text("尚未配对门锁 — 写入钥匙前需先配对门锁。")
                .xFont(.footnote)
                .foregroundStyle(XPalette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .background(XPalette.warn.opacity(XOpacity.wash),
                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 钥匙串卡
    // ═══════════════════════════════════════════════════════

    /// 钥匙串卡 —— 2026-10-24 坚决精简
    ///
    /// 原 App 的 AddkeychainPage/KeychaindetailPage/DelblekeyPage 只做三件事：
    /// **配对钥匙串 · 查看列表 · 删除**。用户裁定「只留配对+列表+删除」。
    ///
    /// 删掉：40pt 图标器皿与辉光 / MAC 小字 / 电量横条与信号读数 / 状态胶囊。
    /// 留下：名字 + 是否已配钥匙 + 一行菜单（写钥匙 / 查钥匙 / 删钥匙 / 删记录）。
    private func dongleCard(_ d: Dongle) -> some View {
        let hasKey = !d.lastKeyLock.isEmpty
        return XPanel(kind: .group) {
            HStack(spacing: XSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name.isEmpty ? "钥匙串" : d.name)
                        .xFont(.body, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Text(hasKey ? "已配钥匙" : "未配钥匙")
                        .xFont(.caption)
                        .foregroundStyle(hasKey ? XPalette.ok : XPalette.textTertiary)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("读取状态") { Task { await readStatus(d) } }
                    Button("给当前门锁写入钥匙") { confirmWriteKey(d) }
                    Button("查询全部钥匙") { Task { await listKeys(d) } }
                    XHairline()
                    Button("删除本锁钥匙", role: .destructive) { confirmDeleteKey(d) }
                    Button("删除记录", role: .destructive) {
                        confirmDestructive("删除这条网关记录？",
                                           "只从本机列表移除这条记录，门锁上的设置不受影响。",
                                           confirmTitle: "删除记录") { removeRecord(d) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: XIcon.md, weight: .medium))
                        .foregroundStyle(XPalette.textSub)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
            }
        }
    }






    // ═══════════════════════════════════════════════════════
    // MARK: - 空态
    // ═══════════════════════════════════════════════════════

    private var emptyState: some View {
        VStack(spacing: XSpace.l) {
            Image(systemName: "key.slash")
                .font(.system(size: XMetric.decorIcon(64), weight: .ultraLight))
                .foregroundStyle(XPalette.textTertiary)
                .accessibilityHidden(true)
            Text("还没有钥匙串")
                .xFont(.title3, weight: .semibold)
                .foregroundStyle(XPalette.text)
            Text("上电后点上方「搜索钥匙串」即可添加")
                .xFont(.subheadline)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
            Button("搜索钥匙串") { Task { await scan() } }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
                .disabled(busy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XSpace.xxl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 逻辑 (与旧实现等价)
    // ═══════════════════════════════════════════════════════

    private func dongleDisplay(_ hex: String) -> String {
        let b = HexKit.bytes(hex).reversed()
        return b.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func reload() { dongles = DB.dongles() }

    private func confirmWriteKey(_ d: Dongle) {
        guard !busy else { return }
        let lockName = app.displayName
        confirmDestructive("写入钥匙",
                           "将把「\(lockName)」的门锁密钥写入钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」。写入后该钥匙串可独立开门, 且本机无法撤销。",
                           confirmTitle: "确认写入") {
            Task { await writeKey(d) }
        }
    }

    private func confirmDeleteKey(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除本锁钥匙",
                           "将清除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」中「\(app.displayName)」的钥匙。删除后该钥匙串无法开这把锁。",
                           confirmTitle: "删除") {
            Task { await deleteKey(d) }
        }
    }

    private func removeRecord(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除记录",
                           "将从本机删除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」(\(dongleDisplay(d.mac))) 的记录。不影响钥匙串硬件本身。",
                           confirmTitle: "删除") {
            DB.removeDongle(d.mac)
            reload()
        }
    }

    private func scan() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.scanForDongle() }
        catch { app.showToast(ErrorText.human(error)) }
        reload()
    }

    private func readStatus(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.readDongleState(mac: d.mac) }
        catch { app.showToast(ErrorText.human(error)) }
        reload()
    }

    private func writeKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        guard !kc.skey.isEmpty, kc.pid != 0 else { app.showToast("请先配对门锁"); return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc, trackId: UInt32(0))
            // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
            app.showToast("设置成功: 该钥匙串现已开启「\(app.displayName)」", tone: .done)
        } catch {
            // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
            app.showToast("失败: " + ErrorText.human(error), tone: .failed)
        }
        reload()
    }

    private func deleteKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
            app.showToast("已删除该门锁的钥匙", tone: .done)
        } catch {
            // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
            app.showToast("失败: " + ErrorText.human(error), tone: .failed)
        }
        reload()
    }

    private func listKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let macs = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            app.showToast(macs.isEmpty ? "没有查询到钥匙" : "共 \(macs.count) 把钥匙")
        } catch {
            app.showToast("失败: " + ErrorText.human(error), tone: .failed)
        }
        reload()
    }
}
