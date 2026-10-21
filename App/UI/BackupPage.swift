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
import UniformTypeIdentifiers
import UIKit

/// 备份页
struct BackupPage: View {
    @EnvironmentObject private var app: AppState

    @State private var exportText = ""
    @State private var importText = ""
    @State private var busy = false
    @State private var showImport = false
    /// 文件选择器（方案 a: iCloud / 本地文件）
    ///
    /// 原来的导入只支持「粘贴文本」—— 用户得先把文件内容复制出来。
    /// 文件选择器让「从 iCloud 云盘 / 我的 iPhone 里选一个 .json」成为一条路径。
    ///
    /// 与粘贴共用同一个解析入口（confirmRestore 的 JSONDecoder），
    /// 不另写一套解析 —— 两条路径最终都产出 BackupBundle。
    @State private var showFilePicker = false
    /// 导出文件选择器（存到 iCloud / 本机）
    ///
    /// 与导入对称: 导入能选文件，导出也该能存文件。
    /// 原来只有「复制到剪贴板」—— 那是给聊天工具用的，
    /// 但备份的正常去处是「存到 iCloud 云盘 / 我的 iPhone」。
    @State private var showFileExporter = false
    @State private var showStudio = false
    @State private var pendingRestore: BackupBundle?

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                statusCard.xScrollLift()
                exportCard.xScrollLift()
                importCard.xScrollLift()
                studioRow.xScrollLift()
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
        // 方案 a: 文件选择器（iCloud 云盘 / 本地）
        //
        // allowedContentTypes 用 .json 与 .data 两种:
        //   .json  正常备份文件
        //   .data  兜底（有些网盘会把 .json 存成 application/octet-stream）
        //
        // allowsMultipleSelection: false —— 备份是单文件，多选没有语义。
        // 导出: 存文件到 iCloud / 本机（与导入对称）
        //
        // defaultFilename 用带日期的名字 —— 多次备份不会互相覆盖，
        // 用户也能一眼看出是哪天的。
        .fileExporter(isPresented: $showFileExporter,
                      document: BackupFile(text: exportText),
                      contentType: .json,
                      defaultFilename: backupFilename) { result in
            if case .success = result {
                // 落盘时更新"上次备份"时间 —— 与 generateBackup 同口径
                DB.store.set("kf_bk_last_export", Int(Date().timeIntervalSince1970 * 1000))
                XHaptics.success()
                app.showToast("已保存到文件")
            } else if case .failure(let e) = result {
                if (e as NSError).code != NSUserCancelledError {
                    app.showToast("保存失败")
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.json, .data],
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
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
                Text("生成一份备份, 存到 iCloud 云盘 / 我的 iPhone，或复制成文本。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                XBusyButton(
                    title: exportText.isEmpty ? "生成备份" : "重新生成",
                    systemImage: exportText.isEmpty ? "doc.badge.plus" : "arrow.clockwise",
                    busy: busy,
                    style: exportText.isEmpty ? .primary : .secondary
                ) {
                    generateBackup()
                }

                // 生成之后才出现两条导出路径 —— 没生成时点它们没有内容可存
                if !exportText.isEmpty {
                    // 主路径: 存文件（iCloud / 本机），与导入的 fileImporter 对称
                    Button {
                        showFileExporter = true
                        XHaptics.tick.impactOccurred()
                    } label: {
                        Label("保存到文件", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                    .accessibilityHint("存到 iCloud 云盘或本机")

                    // 次路径: 复制文本（从聊天工具发给另一台设备时更直接）
                    Button {
                        UIPasteboard.general.string = exportText
                        app.showToast("备份文本已复制")
                    } label: {
                        Label("复制备份文本", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(XSecondaryButtonStyle())
                }
            }
        }
    }

    /// 导出文件名 —— 带日期，多次备份不互相覆盖
    private var backupFilename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        f.dateFormat = "yyyyMMdd-HHmm"
        return "锁管家备份-\(f.string(from: Date()))"
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
                Text("从 iCloud 云盘 / 我的 iPhone 里选备份文件，或直接粘贴备份文本。相同设备会被覆盖, 其它设备保留。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                // 方案 a: 文件选择器（主路径）
                Button {
                    showFilePicker = true
                    XHaptics.tick.impactOccurred()
                } label: {
                    Label("从文件导入", systemImage: "folder")
                }
                .buttonStyle(XSecondaryButtonStyle())
                .accessibilityHint("打开文件选择器，从 iCloud 云盘或本机选备份文件")

                // 粘贴（保留 —— 从聊天工具收到备份文本时更直接）
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

    /// 文件选择器的结果处理
    ///
    /// 要点:
    ///   · fileImporter 给的是**临时可访问 URL**，必须 startAccessingSecurityScopedResource
    ///     否则 read 会失败（这是 iOS 沙盒规则，不是可选步骤）
    ///   · 与粘贴路径共用同一个 JSONDecoder 入口 —— 两条路产出同一个 BackupBundle
    ///   · 任何失败都给 toast，不静默
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let bundle = try JSONDecoder().decode(BackupBundle.self, from: data)
                pendingRestore = bundle
                XHaptics.tick.impactOccurred()
            } catch {
                app.showToast("文件读取失败或格式不对")
            }

        case .failure(let error):
            // 用户取消不报错（NSUserCancelledError）
            if (error as NSError).code != NSUserCancelledError {
                app.showToast("没能打开文件")
            }
        }
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
        // XRow 自带 action 参数 (内部就是 Button), 不需要外层 Button + 手搓背景
        XPanel(kind: .group) {
            XRow(
                systemImage: "wrench.and.screwdriver",
                title: "备份工作室",
                subtitle: "导出向导 / 恢复预演 / 完整性校验",
                showsChevron: true
            ) {
                showStudio = true
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 备份文件（导出用）
// ═══════════════════════════════════════════════════════════════════════
//
// 用 Transferable + DataRepresentation 而不是 FileDocument ——
// ExportCenter 里已经有 5 个同款（ExportCSVFile / ExportJSONFile / …），
// 复用已验证的模式，不引入第二套文件表示。
struct BackupFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.json) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { _ in "备份.json" }
    }
}
