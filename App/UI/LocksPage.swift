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

    var body: some View {
        List {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LockArchive.displayName(kc) + (isCurrent ? ", 当前锁" : ""))
    }

    private func subtitle(_ kc: Keychain, _ snap: StatusSnapshotData?) -> String {
        var parts: [String] = []
        if let p = snap?.powerLevel, p >= 0 { parts.append("电量 \(p)%") }
        if let f = snap?.firmware, !f.isEmpty { parts.append("固件 \(f)") }
        let pwds = DB.listPwds(kc.mac).count
        let fps = DB.listFps(kc.mac).count
        if pwds + fps > 0 { parts.append("\(pwds + fps) 份凭证") }
        return parts.isEmpty ? "未连接过" : parts.joined(separator: " · ")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private func reload() {
        locks = DB.keychains().filter { !LockArchive.isHidden($0.mac) }
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
