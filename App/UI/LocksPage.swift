//
//  LocksPage.swift
//  设备管理 · 全新重写 (2026-10-21)
//
//  门里「这台锁」→ 设备管理的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 DeviceManageView (428 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 分组折叠 + 多选 + 批量工具条 + 拖动排序 + 长按菜单 + 隐藏/置顶
//        —— 功能齐全但入口分散。
//
//  新版: 一个可排序列表, 每行一个滑动菜单
//    · 列表即真相: 顺序就是启动顺序
//    · 左滑: 隐藏 / 删除
//    · 右滑: 置顶
//    · 长按: 进入编辑态拖动
//    · 批量收进 toolbar (需要时才出现)
//
//  设计原则:
//    · 系统 List 的 swipeActions 而不是自造菜单
//    · 拖动排序用系统 .onMove, 不自己算
//    · 每行显示"当下值" (电量/状态), 不是只有名字
//

import SwiftUI

/// 设备管理 —— 门里「这台锁」→ 设备管理
struct LocksPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var locks: [Keychain] = []
    @State private var editMode: EditMode = .inactive
    @State private var shareTarget: Keychain?
    @State private var showAdd = false
    @State private var hiddenLocks: [Keychain] = []
    /// 待确认解绑的门锁。解绑会删除本机保存的密钥，不可撤销。
    @State private var confirmUnpair: Keychain?

    var body: some View {
        List {
            if locks.isEmpty {
                // 空状态：0 把锁时只剩一行"0 把锁"是没用的界面。
                // 告诉用户下一步做什么，并直接给出入口。
                Section {
                    XEmptyState(systemImage: "lock.slash",
                                title: "还没有门锁",
                                message: "配对之后，这里会列出你所有的门锁，\n顺序就是启动时默认选中的顺序。",
                                actionTitle: "去配对",
                                action: { showAdd = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(locks) { kc in
                    lockRow(kc)
                }
                .onMove { from, to in
                    var arr = locks
                    arr.move(fromOffsets: from, toOffset: to)
                    locks = arr
                    persistOrder()
                }
                .onDelete { idx in
                    for i in idx {
                        let kc = locks[i]
                        LockArchive.setHidden(kc.mac, true)
                    }
                    reload()
                }
            } header: {
                Text("\(locks.count) 把锁")
            } footer: {
                Text("顺序就是启动时默认选中的顺序。左滑可隐藏, 长按可拖动排序。")
            }

            // ═══ 已隐藏 ═══
            //
            // 没有这一段的话，"左滑隐藏"是不可逆的：
            // 隐藏的锁被 reload() 过滤掉了，而唯一能改 isHidden 的
            // LockProfilePage 只编辑 app.currentMac（当前锁）——
            // 于是那把锁在界面里彻底消失，既不能选、也不能改凭证、更无法恢复。
            // 门锁 App 里"把一把锁弄没了"是严重问题，所以这里必须留出口。
            if !hiddenLocks.isEmpty {
                Section {
                    ForEach(hiddenLocks) { kc in
                        HStack(spacing: XSpace.m) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: XIcon.sm, weight: .medium))
                                .foregroundStyle(XPalette.textTertiary)
                                .accessibilityHidden(true)
                            Text(LockArchive.displayName(kc))
                                .xFont(.subheadline)
                                .foregroundStyle(XPalette.textSub)
                                .lineLimit(1)
                            Spacer(minLength: XSpace.s)
                            Button("取消隐藏") {
                                LockArchive.setHidden(kc.mac, false)
                                reload()
                                XHaptics.tick.impactOccurred()
                            }
                            .xFont(.footnote, weight: .medium)
                            .foregroundStyle(XPalette.accentText)
                            .accessibilityLabel("取消隐藏 " + LockArchive.displayName(kc))
                        }
                        .frame(minHeight: XHit.min)
                    }
                } header: {
                    Text("已隐藏 \(hiddenLocks.count) 把")
                } footer: {
                    Text("隐藏的锁不出现在上面的列表里，但数据仍在。点「取消隐藏」就可以放回来。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
        .navigationTitle("设备管理")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "完成" : "排序") {
                    withAnimation(XMotion.quick) {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    XHaptics.tick.impactOccurred()
                }
                .accessibilityLabel(editMode.isEditing ? "完成排序" : "进入排序")
            }
        }
        .onAppear { reload() }
        .sheet(item: $shareTarget) { kc in
            ShareToAndroidView(kc: kc)
                .environmentObject(app)
        }
        // onDismiss 必须重载：配对成功后本页的 locks 是 @State 缓存，
        // 父视图的 onAppear 不会因为 sheet 关闭而重新触发 ——
        // 不加这一句，刚配好的门锁不会出现在列表里。
        .confirmationDialog(
            "解除绑定？",
            isPresented: Binding(get: { confirmUnpair != nil }, set: { if !$0 { confirmUnpair = nil } }),
            titleVisibility: .visible,
            presenting: confirmUnpair
        ) { kc in
            Button("解除绑定", role: .destructive) { unpair(kc) }
            Button("取消", role: .cancel) { confirmUnpair = nil }
        } message: { kc in
            Text("将从本机删除「\(LockArchive.displayName(kc))」的密钥与全部本机设置，不可撤销。\n门锁里的密码/指纹不受影响 —— 要删那些得连上锁单独操作。")
        }
        .sheet(isPresented: $showAdd, onDismiss: { reload() }) {
            NavigationStack {
                AddLockPage().environmentObject(app)
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 行
    // ═══════════════════════════════════════════════════════

    private func lockRow(_ kc: Keychain) -> some View {
        let isCurrent = kc.mac == app.currentMac
        let snap = DB.readStatus(kc.mac)
        return HStack(spacing: XSpace.m) {
            Image(systemName: isCurrent ? "lock.fill" : "lock")
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(isCurrent ? XPalette.accent : XPalette.textSub)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: XSpace.xs) {
                    Text(LockArchive.displayName(kc))
                        .xFont(.body)
                        .foregroundStyle(XPalette.text)
                        .lineLimit(1)
                    if isCurrent {
                        XStatusPill(text: "当前", tone: .accent)
                    }
                }
                Text(subtitle(kc, snap))
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 右侧状态簇 —— 电量与锁态
            //
            // 原来电量只混在副标题文字里（"电量 12%"），
            // 低电量没有任何视觉区分，用户扫一眼看不出来哪把锁该换电池。
            // 锁态 (rc) 也从没在这一行出现过。
            VStack(alignment: .trailing, spacing: 2) {
                if let p = snap?.powerLevel, p >= 0 {
                    HStack(spacing: 2) {
                        Image(systemName: batteryIcon(p))
                            .font(.system(size: XIcon.xs, weight: .medium))
                        Text(String(p) + "%")
                            .xFont(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(batteryTone(p))
                }
                if let rc = snap?.rc {
                    Text(lockStateText(rc))
                        .xFont(.caption2)
                        .foregroundStyle(lockStateTone(rc))
                }
            }
        }
        .padding(.vertical, XSpace.xxs)
        .contentShape(Rectangle())
        .onTapGesture {
            app.select(kc.mac)
            XHaptics.tick.impactOccurred()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                LockArchive.setHidden(kc.mac, true)
                reload()
                XHaptics.trigger.impactOccurred()
            } label: {
                Label("隐藏", systemImage: "eye.slash")
            }
            if !isCurrent {
                Button {
                    app.select(kc.mac)
                    XHaptics.tick.impactOccurred()
                } label: {
                    Label("设为当前", systemImage: "pin")
                }
                .tint(XPalette.accent)
            }
            Button {
                shareTarget = kc
                XHaptics.tick.impactOccurred()
            } label: {
                Label("分享给安卓", systemImage: "qrcode")
            }
            .tint(XPalette.ok)
            // ═══ 解除绑定 ═══
            //
            // DB.removeDevice 是一份写得很完整的解绑实现（清钥匙串、待配对记录、
            // 每锁键族、全局指针、顺序表并交棒默认锁），但**全仓零调用**，
            // 也没有别的解绑路径 —— 等于一旦配对就再也删不掉。
            // 卖手机、搬家换锁之后，那把锁的密钥会永远留在本机。
            Button {
                confirmUnpair = kc
                XHaptics.tick.impactOccurred()
            } label: {
                Label("解除绑定", systemImage: "trash.slash")
            }
            .tint(XPalette.danger)
        }
        // ⚠ 这里不能只写名字。
        // .accessibilityElement(children: .combine) 之后再给 .accessibilityLabel，
        // 会**完全覆盖**合并出来的内容 —— 电量百分比和锁态对 VoiceOver 用户直接丢失。
        // 所以显式把这一行看得见的信息都读出来。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel(kc, snap: snap, isCurrent: isCurrent))
    }

    /// 一行里**看得见**的信息，VoiceOver 也要能听到。
    /// 顺序按信息重要度：名称 → 是否当前 → 锁态 → 电量。
    private func accessibilityRowLabel(_ kc: Keychain, snap: StatusSnapshotData?, isCurrent: Bool) -> String {
        var parts: [String] = [LockArchive.displayName(kc)]
        if isCurrent { parts.append("当前锁") }
        if let rc = snap?.rc { parts.append(lockStateText(rc)) }
        if let p = snap?.powerLevel, p >= 0 { parts.append("电量 \(p)%") }
        return parts.joined(separator: "，")
    }

    /// 电量图标
    private func batteryIcon(_ p: Int) -> String {
        if p <= 10 { return "battery.0" }
        if p <= 25 { return "battery.25" }
        if p <= 50 { return "battery.50" }
        if p <= 75 { return "battery.75" }
        return "battery.100" }
    /// 电量配色 —— 低电量必须醒目
    private func batteryTone(_ p: Int) -> Color {
        if p <= 20 { return XPalette.danger }
        if p <= 40 { return XPalette.warn }
        return XPalette.textSub
    }
    /// 锁态文案（来自 StatusSnapshotData.rc，与门面同一口径）
    private func lockStateText(_ rc: Int) -> String {
        switch rc {
        case 0: return "已锁"
        case 21, 27: return "反锁"
        case 25: return "忙碌"
        case 26: return "防拆"
        default: return "状态 " + String(rc)
        }
    }
    private func lockStateTone(_ rc: Int) -> Color {
        switch rc {
        case 0: return XPalette.ok
        case 21, 27: return XPalette.warn
        case 25, 26: return XPalette.danger
        default: return XPalette.textTertiary
        }
    }

    private func subtitle(_ kc: Keychain, _ snap: StatusSnapshotData?) -> String {
        var parts: [String] = []
        // 型号 —— Keychain.pidName 一直有，但列表从没显示过
        if !kc.pidName.isEmpty { parts.append(kc.pidName) }
        if let f = snap?.firmware, !f.isEmpty { parts.append("固件 \(f)") }
        // 凭证拆分显示 —— 原来只有总数，看不出构成
        let pwds = DB.listPwds(kc.mac).count
        let fps = DB.listFps(kc.mac).count
        if pwds + fps > 0 { parts.append("\(pwds) 密码 · \(fps) 指纹") }
        // 配对时间 —— Keychain.pairedAt 从没显示过
        if !kc.pairedAt.isEmpty { parts.append("配对于 " + kc.pairedAt) }
        return parts.isEmpty ? "未连接过" : parts.joined(separator: " · ")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    /// 解绑一台门锁。
    ///
    /// 只清本机这一侧：钥匙串、待配对记录、每锁键族、全局指针都删掉，
    /// 锁端真正的凭证（密码/指纹）不受影响 —— 这一点必须在确认文案里说清，
    /// 否则用户会以为"解绑 = 锁上那些也删了"，从而把一把还带着自己指纹的锁卖掉。
    private func unpair(_ kc: Keychain) {
        let name = LockArchive.displayName(kc)
        DB.removeDevice(kc.mac)
        // 解绑的是当前锁 → 让 AppState 重新指一把，否则整机还盯着一个不存在的 mac
        if app.currentMac == kc.mac { app.loadDevices() }
        confirmUnpair = nil
        reload()
        XHaptics.trigger.impactOccurred()
        app.showToast("已解除绑定「\(name)」")
    }

    private func reload() {
        let all = DB.keychains()
        locks = all.filter { !LockArchive.isHidden($0.mac) }
        hiddenLocks = all.filter { LockArchive.isHidden($0.mac) }
    }

    private func persistOrder() {
        var order = locks.map { $0.mac }
        // 隐藏的锁排在后面, 保持不丢
        let hidden = DB.keychains().filter { LockArchive.isHidden($0.mac) }.map { $0.mac }
        order += hidden
        DB.store.setCodable("kf_lock_order", order)
        XHaptics.tick.impactOccurred()
    }
}
