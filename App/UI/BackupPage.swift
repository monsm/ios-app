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
    /// 文件选择器让「从 iCloud 云盘 / 我的 iPhone 里选一份备份」成为一条路径。
    ///
    /// 与粘贴共用同一个入口：`applyParsed` → `BackupStudio.parsePreview`，
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
            VStack(spacing: XSpace.section) {
                if let b = pendingRestore {
                    restoreConfirmCard(b)
                }
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
        // allowedContentTypes 用 .item（任意文件）:
        //   本 App 导出的备份是 `.enc` 文件，系统不认识这个扩展名 ——
        //   限 .json/.data 时它在选择器里是**灰的**，用户点了不选中，
        //   表现成"弹了选择器但选不动"。内容正确性由 parsePreview 把关，
        //   不靠文件类型筛。
        //
        // allowsMultipleSelection: false —— 备份是单文件，多选没有语义。
        // 导出: 存文件到 iCloud / 本机（与导入对称）
        //
        // defaultFilename 用带日期的名字 —— 多次备份不会互相覆盖，
        // 用户也能一眼看出是哪天的。
        .fileExporter(isPresented: $showFileExporter,
                      item: BackupFile(text: exportText),
                      contentTypes: [.data],   // 不写 .json：那会把扩展名强行改成 .json，与工作室的 .enc 不一致
                      defaultFilename: backupFilename) { result in
            if case .success = result {
                // 落盘时更新"上次备份"时间 —— 与 generateBackup 同口径
                Milestones.recordBackup()
                // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
                app.showToast("已保存到文件", tone: .done)
            } else if case .failure(let e) = result {
                if (e as NSError).code != NSUserCancelledError {
                    // 错误对象就在手边，别只报"保存失败" —— 用户没法据此做任何事。
                    app.showToast("保存失败：" + ErrorText.human(e))
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.item],   // 备份文件是 .enc —— 之前限 .json/.data，系统把它判成未知类型直接灰掉，点了不选中
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showStudio) {
            BackupStudioView().environmentObject(app)
        }
        // 选择器收起后再呈现确认框 —— 见 handleFileImport 里的说明。

        // 确认改成**页内卡片**（见 body 顶部 restoreConfirmCard）。
        // 原来用 .confirmationDialog：文件选择器刚关就弹——两层模态套着，
        // SwiftUI 会把第二层丢掉，表现成"选了文件什么都没发生"。
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

    /// 文案唯一实现在 BackupStudioKit.lastBackupText（原来这里与 FirmwarePage 各写一份）。
    private var lastBackupText: String { BackupStudioKit.lastBackupText }

    private var backupHint: String {
        let d = daysSinceBackup
        if d < 0 { return "备份包含全部钥匙与设置, 全程离线加密。" }
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
        // 与工作室同一套命名（前导 "锁管家_" + 结尾 ".enc"）——
        // 否则从这一页导出的文件，工作室的 isOurBackup 认不出来，
        // 既不出现在本地备份列表里，也不参与保留期清理。
        return BackupStudio.fileName()
    }

    private func generateBackup() {
        busy = true
        defer { busy = false }
        let payload = BackupKit.collectAll()
        // 原来写 try? 把错误吞掉了，只报"备份生成失败" —— 三种失败原因长得一样。
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            app.showToast("备份生成失败：" + ErrorText.human(error))
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            app.showToast("备份生成失败：编码后的内容不是有效文本 · 可能有一条损坏记录，请先跑一次「数据体检」再备份")
            return
        }
        exportText = text
        Milestones.recordBackup()
        XHaptics.success()
        app.showToast("备份已生成, 点一次复制")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 导入
    // ═══════════════════════════════════════════════════════

    /// 页内恢复确认。
    ///
    /// 为什么不做成弹窗：文件选择器与它的确认框是**两层连续模态**，
    /// SwiftUI 在上一层还没消失时会丢掉下一层 —— 用户看到的就是"选了没反应"。
    /// 页内卡片没有这个问题，而且选完文件后信息就在眼前，不必再弹一次。
    private func restoreConfirmCard(_ b: BackupBundle) -> some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("确认恢复这份备份？")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                let memberCount = b.members?.count ?? 0
                Text("备份时间 \(b.at) · \(b.devices.count) 台设备"
                     + (memberCount == 0 ? "" : " · \(memberCount) 位成员"))
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // "相同设备会被覆盖"这句话不够 —— saveLedger 是**整表覆盖**，
                // 所以备份里没包含的钥匙也不会保留。不写明就是骗人。
                Text("该设备的钥匙会**以备份为准**：备份里没有的不会保留。其它设备不受影响。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                // 这一页只有"覆盖式"恢复。想保留本机新增的钥匙，得去工作室选「合并」——
                // 不写明，用户会以为这里也能合并。
                Text("想保留本机新增的钥匙，请用「备份工作室」的**合并**恢复。恢复前会自动留一个回滚点。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: XSpace.s) {
                    Button {
                        pendingRestore = nil
                        XHaptics.tick.impactOccurred()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                    .buttonStyle(XSecondaryButtonStyle())

                    Button {
                        applyRestore(b)
                        pendingRestore = nil
                    } label: {
                        Label("确认恢复", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                }
            }
        }
    }

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
                    .xFontExact(.footnote.monospaced())
                    .scrollContentBackground(.hidden)
                    .background(XPalette.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
                    .frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if importText.isEmpty {
                            Text("在此粘贴备份文本")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
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
        let text = importText
        showImport = false
        // 与文件导入走**同一个入口**（parsePreview）。原先这里裸 JSONDecoder，
        // 于是"把加密备份的内容粘贴进来"永远失败 —— 而界面上根本没说过只收明文。
        if BackupStudio.needsPassword(text) {
            promptSecret("这份备份设了口令", "输入导出时设置的口令才能解开。",
                         placeholder: "备份口令") { pw in
                applyParsed(text: text, password: pw.isEmpty ? nil : pw)
            }
        } else {
            applyParsed(text: text, password: nil)
        }
    }

    /// 文件选择器的结果处理
    ///
    /// 要点:
    ///   · fileImporter 给的是**临时可访问 URL**，必须 startAccessingSecurityScopedResource
    ///     否则 read 会失败（这是 iOS 沙盒规则，不是可选步骤）
    ///   · 与粘贴路径共用同一个入口 `applyParsed` → `parsePreview` —— 两条路产出同一个 BackupBundle
    ///   · 任何失败都给 toast，不静默
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // ⚠ 不能直接 JSONDecoder 解 —— 本 App 导出的备份是 **.enc 加密文本**，
            // 裸解必然失败，用户看到的就是"选了文件但什么都没发生"。
            // 正确入口只有一个：BackupStudio.parsePreview（剥注释头 → 解密 → 校验哈希 → schema 检查）。
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
                app.showToast("这个文件读不出文本内容 · 备份文件是文本格式")
                return
            }

            if BackupStudio.needsPassword(text) {
                // 加密备份必须先问口令。取消就是取消，不猜。
                promptSecret("这份备份设了口令", "输入导出时设置的口令才能解开。",
                             placeholder: "备份口令") { pw in
                    applyParsed(text: text, password: pw.isEmpty ? nil : pw)
                }
            } else {
                applyParsed(text: text, password: nil)
            }

        case .failure(let error):
            // 用户取消不报错（NSUserCancelledError）
            if (error as NSError).code != NSUserCancelledError {
                app.showToast("没能打开文件")
            }
        }
    }

    /// 解析并挂到待确认。任何一步不过（口令/哈希/schema）都不写库。
    private func applyParsed(text: String, password: String?) {
        do {
            let (_, bundle) = try BackupStudio.parsePreview(text: text, password: password)
            pendingRestore = bundle
            XHaptics.tick.impactOccurred()
        } catch {
            app.showToast("导入被拦下: " + ErrorText.human(error))
        }
    }
    private func applyRestore(_ bundle: BackupBundle) {
        // 恢复前先留一个回滚点 —— 工作室的恢复流程一直这么做（421），
        // 而这一页原来**直接 restoreAll**：整表覆盖且不可撤销。
        // 同一个动作，两条路径一个可撤回一个不可撤回，没有道理。
        let rollbackOk = BackupStudio.makeRollbackPoint()
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        if bundle.globals?.appearance != nil { app.reloadAppearance() }
        XHaptics.success()
        // restoreAll 会**静默跳过** "MAC 不合法 / 没有钥匙材料" 的设备，
        // 而它只返回新增与覆盖两个数 —— 只报这两个，用户会以为全都恢复了。
        // 差多少就说明多少。
        let skipped = bundle.devices.count - (r.imported + r.overwritten)
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)"
                       + (skipped > 0 ? " · \(skipped) 台被跳过 (缺钥匙材料)" : "")
                       + (rollbackOk ? " · 已留回滚点" : ""))
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
                subtitle: "导出 / 恢复 / 校验",
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
        DataRepresentation(exportedContentType: UTType.data) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { _ in "锁管家备份.enc" }
    }
}
