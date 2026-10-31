// BackupScreen.swift —— 备份与恢复。这一屏的主动作是「生成备份」。
//
// 这屏干什么：导出一整段本机数据（门锁 / 凭证 / 成员 / 外观档），或从一段备份文本恢复。
// 备份文件含明文门锁密钥 —— 拿到它的人不需要你的手机就能开你家门，所以危险说明写在最上面。
// 数据从哪来：SettingsStore.shared（上次备份时刻 / 加密开关）+ AppModel（本机数据计数）。
// 主动作：唯一 signal 填充是「生成备份」。恢复是破坏性动作，走描边 + 二次确认。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    private var store: SettingsStore { SettingsStore.shared }

    @State private var exportText = ""
    @State private var importText = ""
    /// 导出侧口令：生成加密备份用。
    @State private var exportPassword = ""
    /// 导入侧口令：解开加密备份用。两处分开存 —— 同一段文本在两侧含义不同。
    @State private var importPassword = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var showRestoreConfirm = false
    @State private var restoreDone: (added: Int, merged: Int)?
    /// 恢复被拦下的原因。不写「失败了」三个字，写清是哪一道闸拦的。
    @State private var restoreError: String?
    /// 系统文件选择器：导出到「文件 / iCloud 云盘」，或从文件导入。
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc: BackupDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "备份与恢复", tone: tone, status: status)
                studioEntry
                exportPanel
                importPanel
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: exportDoc,
                      contentType: .plainText, defaultFilename: backupFileName) { result in
            switch result {
            case .success(let url):
                AppToast.shared.show("已存到 \(url.lastPathComponent)", tone: .ok)
            case .failure(let e):
                restoreError = "存文件失败：" + e.localizedDescription
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.plainText, .json]) { result in
            switch result {
            case .success(let url): readBackupFile(url)
            case .failure(let e): restoreError = "选文件失败：" + e.localizedDescription
            }
        }
        .confirmationDialog("恢复这份备份？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复（合并，只增不删）") { runImport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("导入是合并：本机已有的凭证会保留，同名冲突取本机。若备份里带本机密码摘要，本机密码会被替换成它（可能回滚到旧值）。")
        }
    }

    // MARK: 备份工作室入口（WebDAV / 多份保留 / 换机迁移 / 自检）
    private var studioEntry: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "备份工作室")
                SettingsNote(text: "本机多份备份文件、WebDAV 同步、换机迁移包与数据自检都在工作室里。")
                VOutlineButton(title: "打开备份工作室", systemImage: "square.stack.3d.up") {
                    router.request(.dest(.backupStudio))
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 页头
    private var tone: Tone { store.lastBackupAt == nil ? .attention : .ok }

    private var status: String {
        guard let at = store.lastBackupAt else {
            return "本机从未生成过备份 · 手机丢失或重装即不可恢复"
        }
        return "上次备份 \(TimeFormat.dayShort(at)) \(TimeFormat.clock(at)) · \(TimeFormat.ago(at))"
    }

    // MARK: 主角：导出
    private var exportPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "全量备份", trailing: store.encryptBackup ? "加密" : "明文")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    // 危险说明放最上面：这一屏最重要的信息不是"怎么点按钮"
                    HStack(alignment: .top, spacing: V.S.gapS) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(V.F.icon15)
                            .foregroundStyle(V.C.critical)
                            .accessibilityHidden(true)
                        Text(store.encryptBackup
                             ? "加密备份也要当密钥文件对待：口令一旦泄露，文件就是明文门锁密钥（skey / pin / 密码）。别发聊天软件，别放共享文件夹。"
                             : "明文备份含门锁密钥（skey / pin / 密码）。任何人拿到它就能开你家门，不需要你的手机 —— 别发聊天软件，别放共享文件夹。")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.critical)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingRule()

                    VReadingGrid(items: [
                        .init(label: "门锁", value: "\(app.lock == nil ? 0 : 1)", unit: "把"),
                        .init(label: "凭证", value: "\(app.keys.count)", unit: "枚"),
                        .init(label: "成员", value: "\(app.members.count)", unit: "位"),
                        .init(label: "记录缓存", value: "\(app.entries.count)", unit: "条"),
                    ], columns: 2)
                    .padding(.top, V.S.gapXS)

                    SettingRule()

                    SettingToggle(
                        label: "加密备份",
                        note: "开启后需要设一个密码才能生成。忘记密码 = 这份备份永久作废，所以默认关闭。",
                        isOn: settingsBinding(\.encryptBackup)
                    )

                    if store.encryptBackup {
                        VInset {
                            SecureField("备份密码（至少 8 位）", text: $exportPassword)
                                .font(V.F.body)
                                .textContentType(.newPassword)
                                .accessibilityLabel("备份密码")
                        }
                        if !exportPassword.isEmpty, exportPassword.count < 8 {
                            VStatusLine(tone: .attention, text: "至少 8 位 —— 否则加密形同虚设")
                        }
                    }

                    VActionButton(title: "生成备份", systemImage: "doc.text", busy: exporting) {
                        generate()
                    }
                    .disabled(store.encryptBackup && exportPassword.count < 8)

                    if !exportText.isEmpty {
                        SettingRule()
                        VStack(alignment: .leading, spacing: V.S.gapXS) {
                            Text("已生成")
                                .font(V.F.unit)
                                .foregroundStyle(V.C.text3)
                                .tracking(0.6)
                            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                                Spacer(minLength: 0)
                                VReading(value: "\(exportText.count)", unit: "字符", font: V.F.number17)
                            }
                            Text(exportText)
                                .font(V.F.footnote.monospaced())
                                .foregroundStyle(V.C.text2)
                                .lineLimit(4)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                            HStack(spacing: V.S.gapS) {
                                VOutlineButton(title: "复制备份文本", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = exportText
                                }
                                VOutlineButton(title: "存到文件", systemImage: "square.and.arrow.up") {
                                    exportDoc = BackupDoc(text: exportText)
                                    showExporter = true
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 恢复
    private var importPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "恢复")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    if importing {
                        VBusyRow(text: "正在解密并校验备份 · 不要离开")
                        SettingRule()
                    }
                    if let restoreError {
                        VStatusLine(tone: .critical, text: restoreError)
                        SettingRule()
                    }
                    if let r = restoreDone {
                        VStatusLine(tone: .ok, text: "已恢复：新增 \(r.added) 项，合并 \(r.merged) 项")
                        SettingRule()
                    }
                    SettingsNote(text: "粘贴备份文本。导入是合并（只增不删）—— 本机已有的凭证会保留，同名冲突取本机。门锁本身无需重置。")
                    VInset {
                        TextField("粘贴备份文本", text: $importText, axis: .vertical)
                            .font(V.F.footnote.monospaced())
                            .lineLimit(3 ... 6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("备份文本")
                    }
                    VInset {
                        SecureField("备份密码（导出时设过密码的才需要填）", text: $importPassword)
                            .font(V.F.body)
                            .accessibilityLabel("备份密码")
                    }
                    HStack(spacing: V.S.gapS) {
                        VOutlineButton(title: "从文件选择", systemImage: "folder") {
                            showImporter = true
                        }
                        VOutlineButton(title: "从剪贴板粘贴", systemImage: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string, !s.isEmpty {
                                importText = s
                            }
                        }
                    }
                    VOutlineButton(title: "恢复这份备份", systemImage: "arrow.down.doc") {
                        showRestoreConfirm = true
                    }
                    .disabled(importText.isEmpty)
                    .opacity(importText.isEmpty ? 0.4 : 1)

                    if importText.isEmpty {
                        SettingsNote(text: "还没有备份文本。下一步：在上面点「生成备份」，再回来把文本粘到这里 —— 或者在换机时把上一条手机上的备份文本复制过来。")
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: - 动作

    private func generate() {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            // 真链路：collectAll（全部 kf_* 表）→ canonical（与小程序互通）→ 可选加密信封。
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            exportText = store.encryptBackup
                ? try CryptoBox.encryptText(plain, password: exportPassword)
                : plain
            // 980：只有真正生成成功才记一次备份（失败不记）。
            Milestones.recordBackup()
        } catch {
            restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 导出文件名：锁名 + 日期，避免「文件」里出现一叠同名 backup.txt。
    private var backupFileName: String {
        let name = app.lock?.name ?? "锁管家"
        let day = TimeFormat.dayKey(Int64(Date().timeIntervalSince1970 * 1000))
        return "lockkeeper-" + name + "-" + day
    }

    /// 从系统文件选择器读回一段备份文本（安全作用域 URL 必须成对开关）。
    private func readBackupFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                restoreError = "这个文件是空的 —— 可能不是备份文件。"
                return
            }
            importText = text
            restoreError = nil
            AppToast.shared.show("已读入 \(url.lastPathComponent)", tone: .ok)
        } catch {
            restoreError = "读文件失败：" + error.localizedDescription
        }
    }

    private func runImport() {
        guard !importText.isEmpty, !importing else { return }
        guard importText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            restoreError = "这段文本不是备份 —— 备份以 { 开头。可能粘错了内容，或复制时被截断。"
            restoreDone = nil
            return
        }
        let password = importPassword.isEmpty ? nil : importPassword
        restoreError = nil
        importing = true
        Task { @MainActor in
            defer { importing = false }
            do {
                // 真链路：解密（若带口令）→ schema 升级 → checksum 校验 → 合并恢复（只增不删）。
                let parsed = try BackupStudio.parsePreview(text: importText, password: password)
                let r = BackupStudio.restore(parsed.bundle)
                restoreDone = (added: r.imported, merged: r.overwritten)
                importText = ""
                await app.reload(refreshStatus: false)
            } catch {
                restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                restoreDone = nil
            }
        }
    }
}

// MARK: - 系统文件导出（FileDocument）

/// 备份文本的 FileDocument 包装：导出的就是用户看到的那段 JSON / 加密信封。
struct BackupDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
