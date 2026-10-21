//
//  BackupPage.swift
//  备份页 · 全新重写 (2026-10-21)
//
//  门里「这台手机」→ 备份的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 BackupView (247 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 全量备份 Section + 导入恢复 Section + 工作室入口。
//
//  新版: 一张"备份状态卡" + 两个动作
//    · 顶部: 上次备份于何时, 多少天没备份了
//    · 动作: 导出 / 恢复
//    · 工作室入口收到底部 (高级用户才需要)
//
//  设计原则:
//    · 备份的价值是"安心", 所以先回答"我上次备份是什么时候"
//    · 导出与恢复是两个不可逆方向, 视觉上分开
//

import SwiftUI
import UIKit

/// 备份页
struct BackupPage: View {
    @EnvironmentObject private var app: AppState

    @State private var exportText = ""
    @State private var importText = ""
    @State private var busy = false
    @State private var showImport = false
    @State private var showStudio = false
    @State private var pendingRestore: BackupBundle?

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                statusCard
                exportCard
                importCard
                studioRow
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showImport) {
            importSheet
        }
        .sheet(isPresented: $showStudio) {
            BackupStudioView().environmentObject(app)
        }
        .confirmationDialog("恢复会覆盖同名设备", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )) {
            Button("确认恢复", role: .destructive) {
                if let b = pendingRestore { applyRestore(b) }
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 状态卡
    // ═══════════════════════════════════════════════════════

    private var statusCard: some View {
        XPanel(kind: .hero, tone: backupTone) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: backupTone == .ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: XIcon.lg, weight: .medium))
                        .foregroundStyle(backupTone.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastBackupText)
                            .xFont(.title3, weight: .semibold)
                            .foregroundStyle(XPalette.text)
                        Text(backupHint)
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                }
            }
        }
    }

    private var lastBackupMs: Int {
        DB.store.getInt("kf_bk_last_export", 0)
    }

    private var daysSinceBackup: Int {
        guard lastBackupMs > 0 else { return -1 }
        return Int((Date().timeIntervalSince1970 * 1000 - Double(lastBackupMs)) / 86_400_000)
    }

    private var lastBackupText: String {
        let d = daysSinceBackup
        if d < 0 { return "从未备份" }
        if d == 0 { return "今天备份过" }
        if d == 1 { return "昨天备份过" }
        return "\(d) 天前备份过"
    }

    private var backupHint: String {
        let d = daysSinceBackup
        if d < 0 { return "备份包含全部凭证与设置, 全程离线加密。" }
        if d <= 7 { return "备份状态良好。" }
        if d <= 30 { return "建议尽快再备份一次。" }
        return "已经很久没备份了, 建议现在备份。"
    }

    private var backupTone: XToneColor {
        let d = daysSinceBackup
        if d < 0 { return .warn }
        if d <= 7 { return .ok }
        if d <= 30 { return .warn }
        return .danger
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 导出
    // ═══════════════════════════════════════════════════════

    private var exportCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("导出")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text("生成一份加密备份文本, 复制到安全的地方。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                XBusyButton(
                    title: exportText.isEmpty ? "生成备份" : "复制备份文本",
                    systemImage: exportText.isEmpty ? "doc.badge.plus" : "doc.on.doc",
                    busy: busy,
                    style: .primary
                ) {
                    if exportText.isEmpty {
                        generateBackup()
                    } else {
                        UIPasteboard.general.string = exportText
                        app.showToast("备份文本已复制")
                    }
                }
            }
        }
    }

    private func generateBackup() {
        busy = true
        defer { busy = false }
        let payload = BackupKit.collectAll()
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            app.showToast("备份生成失败")
            return
        }
        exportText = text
        DB.store.set("kf_bk_last_export", Int(Date().timeIntervalSince1970 * 1000))
        XHaptics.success()
        app.showToast("备份已生成, 点一次复制")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 导入
    // ═══════════════════════════════════════════════════════

    private var importCard: some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("恢复")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text("粘贴之前导出的备份文本。相同设备会被覆盖, 其它设备保留。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showImport = true
                } label: {
                    Label("粘贴备份文本", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(XSecondaryButtonStyle())
            }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: XSpace.l) {
                TextEditor(text: $importText)
                    .xFont(.footnote.monospaced())
                    .scrollContentBackground(.hidden)
                    .background(XPalette.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
                    .frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if importText.isEmpty {
                            Text("在此粘贴备份文本")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textTertiary)
                                .padding(XSpace.s)
                                .allowsHitTesting(false)
                        }
                    }

                Button("从剪贴板粘贴") {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        importText = s
                    } else {
                        app.showToast("剪贴板是空的")
                    }
                }
                .buttonStyle(XSecondaryButtonStyle())

                XBusyButton(title: "恢复", systemImage: "arrow.down.doc",
                            busy: busy, style: .destructive) {
                    confirmRestore()
                }
                .disabled(importText.isEmpty)

                Spacer()
            }
            .padding(XSpace.gutter)
            .background(XPalette.canvas)
            .navigationTitle("恢复备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showImport = false }
                }
            }
        }
    }

    private func confirmRestore() {
        guard let data = importText.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            app.showToast("备份文本格式不对")
            return
        }
        pendingRestore = bundle
        showImport = false
    }

    private func applyRestore(_ bundle: BackupBundle) {
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        if bundle.globals?.appearance != nil { app.reloadAppearance() }
        XHaptics.success()
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        pendingRestore = nil
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 工作室
    // ═══════════════════════════════════════════════════════

    private var studioRow: some View {
        Button {
            showStudio = true
        } label: {
            XRow(
                systemImage: "wrench.and.screwdriver",
                title: "备份工作室",
                subtitle: "导出向导 / 恢复预演 / 完整性校验",
                showsChevron: true)
            .padding(XSpace.card)
            .background(XPalette.surface,
                        in: RoundedRectangle(cornerRadius: XRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
