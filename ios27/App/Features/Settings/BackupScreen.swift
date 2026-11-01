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
    /// 这份内容是否已知校验和不一致（在**已有的**确认对话框里如实告知，不额外加一步）。
    /// 这里不存布尔确认位：BackupScreen 本来就有 confirmationDialog，
    /// 把风险写进那个对话框即可 —— 用户看到风险再点「恢复」就是一次知情确认。
    @State private var importChecksumMismatch = false
    /// 已按**内容指纹**确认过校验和不一致的那一份（只用一次，恢复后作废）。
    @State private var ackedChecksumFor: String?
    @State private var showRestoreConfirm = false
    /// 选文件后**先解析一次**得到的预演摘要（凭证条数 / 会被跳过的锁数）。
    /// 2026-11-01：原来确认对话框在"选完文件"时就弹，此时还没解析 —— 用户看不到
    /// "包里 8 条、实际只写 3 条"这种差额（SEC-08 会整把锁跳过非法密钥）。
    @State private var importPreviewNote = ""
    /// SEC-08：恢复会改写本机密码摘要，所以要先验当前本机密码。
    @State private var currentPasscode = ""
    @State private var restoreDone: (added: Int, merged: Int, skipped: Int)?
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
            // 先报"这次会写进多少"（预演摘要），再说合并语义与风险。
            if importChecksumMismatch {
                // 如实说两种可能，并给出可操作建议 —— 不吓唬，也不轻描淡写。
                Text(importPreviewNote + "这份备份的校验和对不上。可能是本 App 旧版本导出的包（键序不同，属正常），也可能真的被截断或改动过。\n\n导入是合并：本机已有的凭证会保留，同名冲突取本机。仍要继续吗？")
            } else {
                Text(importPreviewNote + "导入是合并：本机已有的凭证会保留，同名冲突取本机。若备份里带本机密码摘要，本机密码会被替换成它（可能回滚到旧值）。")
            }
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
                                // SEC-11：备份文本含全部 skey —— 录屏/截图时一并遮挡。
                                .captureShield("这里是一份可开门的备份\n屏幕正在被录制或截图，已遮挡")
                            HStack(spacing: V.S.gapS) {
                                VOutlineButton(title: "复制备份文本", systemImage: "doc.on.doc") {
                                    // SEC-05：备份文本可能含全部 skey —— 走带 90 秒过期的统一入口。
                                    Clip.set(exportText)
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
                        // 跳过数必须显示：`restore` 本来就会返回它（SEC-08 拒写非法密钥的锁），
                        // 旧文案只报"新增/合并"，用户看到数字偏小会以为备份不全。
                        VStatusLine(tone: r.skipped > 0 ? .attention : .ok,
                                     text: "已恢复：新增 \(r.added) 项，合并 \(r.merged) 项"
                                         + (r.skipped > 0 ? "，跳过 \(r.skipped) 把锁（密钥格式非法）" : ""))
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
                    if DB.hasPasscode() {
                        // SEC-08：导入会替换本机密码摘要 —— 先验当前密码。
                        VInset {
                            SecureField("当前本机密码（导入会改写它，需先验证）", text: $currentPasscode)
                                .font(V.F.body)
                                .keyboardType(.numberPad)
                                .accessibilityLabel("当前本机密码")
                        }
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
                        // 点开的这一刻就知道校验和状态（checksumState 不需要口令，只解 JSON）：
                        // 明文包能判出来，加密包返回 .absent（那由口令层负责，不归这里判）。
                        importChecksumMismatch = (BackupStudio.checksumState(importText) == .mismatch)
                        // 预演摘要也在这里算：这是**唯一**能同时覆盖"从文件选"与"粘贴"两条入口的位置。
                        // 放在读文件那一刻只能覆盖前者 —— 而粘贴过来的文本不会经过 readBackupFile。
                        importPreviewNote = BackupScreen.previewNote(text: importText, password: importPassword)
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
            // 真链路：collectAll（全部 kf_* 表）→ canonical（与小程序互通）→ 加密信封。
            // SEC-02：备份包里是整库 skey/pins/ekey —— 不允许「没设密码 = 明文」。
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            guard !exportPassword.isEmpty else {
                restoreError = "请先设一个备份密码：这份备份包含能开门的密钥，不允许以明文生成。"
                return
            }
            exportText = try CryptoBox.encryptText(plain, password: exportPassword)
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
        // SEC-30：先查大小再读内容。`String(contentsOf:)` 会**整份读进内存**，
        // 而 parsePreview 里那道 32MB 闸发生在读完之后 —— 选了个超大文件就已经把内存吃满了。
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size <= BackupStudio.maxImportBytes else {
            restoreError = "这个文件 \(size / 1_048_576) MB，超过 \(BackupStudio.maxImportBytes / 1_048_576) MB 上限 —— 正常备份远小于此，请确认选对了文件。"
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                restoreError = "这个文件是空的 —— 可能不是备份文件。"
                return
            }
            importText = text
            restoreError = nil
            // 预演摘要不在这里算 —— 统一放到"点恢复、弹确认之前"那一处（见 restore 按钮），
            // 那样"从文件选"和"粘贴"两条入口都能覆盖到。
            AppToast.shared.show("已读入 \(url.lastPathComponent)", tone: .ok)
        } catch {
            restoreError = "读文件失败：" + error.localizedDescription
        }
    }

    /// 预演摘要：把"这次会写进多少"变成一句人话，供确认对话框开头展示。
    /// 解析失败返回空串（预演只是提前告知，不该阻断 —— 真正的错误由 runImport 报）。
    private static func previewNote(text: String, password: String) -> String {
        guard !text.isEmpty,
              let p = try? BackupStudio.parsePreview(text: text, password: password.isEmpty ? nil : password) else { return "" }
        var note = "这份备份含 \(p.preview.pwdCount) 条密码 / \(p.preview.fpCount) 枚指纹。\n\n"
        if p.preview.skippedLocks > 0 {
            note += "其中 \(p.preview.skippedLocks) 把锁的密钥格式非法，恢复时会整把跳过（这些锁的凭证不会写进本机）。\n\n"
        }
        return note
    }

    private func runImport() {
        guard !importText.isEmpty, !importing else { return }
        // SEC-08：恢复会改写本机密码摘要 —— 必须先用**当前**本机密码确认是本人。
        // 旧实现没有任何前置验证：一份构造过的备份就能装一个攻击者已知的 App 登录密码（持久后门）。
        if DB.hasPasscode(), !DB.verifyPasscode(currentPasscode) {
            restoreError = currentPasscode.isEmpty
                ? "导入备份会替换本机密码。请先在下面填「当前本机密码」再恢复。"
                : "当前本机密码不对 —— 恢复会改写本机密码，必须先验证是本人。"
            restoreDone = nil
            return
        }
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
                // SEC-14：校验和对不上**不硬拦**（旧版本导出的包本来就算不出同一个 FNV），
                // 但也不能静默继续。两道覆盖：
                //   · 明文包：确认对话框里已如实告知（importChecksumMismatch 驱动）；
                //   · 加密包：校验和只有**解密后**才算得出来，对话框那条够不到 ——
                //     所以这里再兜一次，按内容指纹要求确认（内容一变就重新问）。
                let fp = BackupCanonical.fnv1a32Hex(importText)
                if BackupStudio.checksumNeedsAck(parsed.preview.checksum), ackedChecksumFor != fp {
                    ackedChecksumFor = fp
                    restoreError = "这份备份的校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），也可能真被截断或改动过。确认要继续请再点一次「恢复这份备份」。"
                    return
                }
                importChecksumMismatch = false
                ackedChecksumFor = nil   // 一次性：这次恢复完就作废，下次重新判断
                let r = BackupStudio.restore(parsed.bundle)
                restoreDone = (added: r.imported, merged: r.overwritten, skipped: r.skipped)
                importText = ""
                importPreviewNote = ""   // 一次性：恢复完就作废，免得下次选文件前残留旧摘要
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
