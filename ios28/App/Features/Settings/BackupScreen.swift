// BackupScreen.swift —— 备份与恢复。
//
// 两条硬规则：
//   1. 不生成明文备份文件 —— 口令为空就不给导出。
//   2. 导入先预览、再写盘；校验和不匹配只警告，不硬拒（老版本导出的包仍然要能回来）。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct BackupScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var exported: String?
    @State private var importing = false
    @State private var importText = ""
    @State private var importPassword = ""
    @State private var preview: BackupStudio.Preview?
    @State private var message: String?
    @State private var busy = false
    @State private var errorLine: String?
    /// 校验和不一致时的二次确认。Engine 的裁量是「不硬拒、但要用户点头」
    /// （`BackupStudio.checksumNeedsAck`）—— 第一次点「恢复」只弹这一问，确认后才真写盘。
    @State private var checkingChecksum: Bool? = nil
    // A5：系统文件选择器 —— 导出存到「文件」，导入从文件读回。
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc: EnvelopeDocument?

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 备份", back: { dismiss() })

            DisplayLine(text: "把家\n收进一个信封。", size: 34)
                .padding(.top, 16)
            Text("备份包含：门锁钥匙串、凭证台账、成员档案、外观与整理。信封用口令加密，没有口令谁也打不开。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            if !DB.isDecoy, let last = Milestones.lastBackupAt {
                Text("上次备份：\(When.ago(Int64(last.timeIntervalSince1970 * 1000)))")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            SectionHead(index: "01", title: "导出")
            FieldInput(placeholder: "设置一个备份口令（至少 8 位）", text: $passphrase, secure: true)
                // 口令一改，之前那封信就不再对应当前口令了 ——
                // 不清掉的话，用户会拿新口令去解旧信封，或者把旧信封当成新口令的结果发出去。
                .onChange(of: passphrase) { _, _ in
                    if exported != nil {
                        exported = nil
                        message = "口令改了，备份需要重新生成。"
                    }
                }
            HStack(spacing: 10) {
                PrimaryButton(title: busy ? "正在生成…" : "生成加密备份", busy: busy) {
                    Task { export() }
                }
                GhostButton(title: "复制", symbol: "doc.on.doc") {
                    if let exported {
                        Clip.set(exported)
                        message = "已复制 · 90 秒后从剪贴板清除"
                    }
                }
                .frame(width: 110)
                // 还没生成备份时，这个按钮原先是个静默的空操作：点下去什么都不发生。
                .disabled(exported == nil)
                .opacity(exported == nil ? 0.45 : 1)
            }
            .padding(.top, 12)

            if let exported {
                Text("信封 \(exported.count) 字符 · 已加密")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ok)
                    .padding(.top, 8)
                // A5：除了分享面板，还可以直接落到「文件」/iCloud 云盘。
                HStack(spacing: 16) {
                    ShareLink(item: exported) {
                        Text("分享备份文件")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.brass)
                    }
                    Button {
                        exportDoc = EnvelopeDocument(text: exported)
                        showExporter = true
                    } label: {
                        Text("存到文件")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.brass)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            SectionHead(index: "02", title: "恢复")
            Button {
                importing.toggle()
            } label: {
                ContentRow(symbol: "tray.and.arrow.down", tone: .cool,
                           title: importing ? "收起" : "从文本恢复",
                           subtitle: "粘贴备份信封与口令，先预览再写入", chevron: true)
            }
            .buttonStyle(.plain)
            // A5：备份文件也可以不经过剪贴板 —— 直接从「文件」里选。
            Button {
                showImporter = true
            } label: {
                ContentRow(symbol: "folder", tone: .cool,
                           title: "从文件选择",
                           subtitle: "在「文件」里找到备份文件，读回来还是要先预览", chevron: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if importing {
                TextEditor(text: $importText)
                    .type(T.F.mono)
                    .frame(height: 130)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous),
                                 tint: GlassMetrics.tint)
                    .padding(.top, 10)
                    // 内容或口令一改，刚才那份预览就不再是「这份」备份的预览了。
                    .onChange(of: importText) { _, _ in preview = nil }

                FieldInput(placeholder: "备份口令", text: $importPassword, secure: true)
                    .padding(.top, 10)
                    .onChange(of: importPassword) { _, _ in preview = nil }

                HStack(spacing: 10) {
                    GhostButton(title: "预览", symbol: "eye") {
                        Task { await doPreview() }
                    }
                    GhostButton(title: "恢复", symbol: "arrow.down.to.line") {
                        Task { await doRestore() }
                    }
                }
                .padding(.top, 10)
                // 解密要跑 PBKDF2：连点两次会并发解两遍，甚至边预览边写盘。
                .disabled(busy)
                .opacity(busy ? 0.55 : 1)

                if let preview {
                    GlassSurface() {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("这份备份里有")
                                .type(T.F.kicker)
                                .foregroundStyle(T.C.ink3)
                            Text("\(preview.macs.count) 把锁 · \(preview.pwdCount) 个密码 · \(preview.fpCount) 个指纹 · \(preview.memberCount) 位成员")
                                .type(T.F.callout)
                                .foregroundStyle(T.C.ink)
                            Text("校验和：" + checksumLabel(preview.checksum) + " · schema \(preview.schema)")
                                .type(T.F.caption)
                                .foregroundStyle(checksumTint(preview.checksum))
                            if preview.skippedLocks > 0 {
                                Text("\(preview.skippedLocks) 把锁会被跳过（钥匙不完整）")
                                    .type(T.F.caption)
                                    .foregroundStyle(T.C.danger)
                            }
                            if BackupStudio.checksumNeedsAck(preview.checksum) {
                                Text("校验和对不上：内容可能与导出时不同，也可能是旧版本算法。恢复前会再确认一次。")
                                    .type(T.F.caption)
                                    .foregroundStyle(T.C.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 12)
                }
            }

            if let message {
                Text(message)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 14)
            }
            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("导入是「只增不减」：本机已有的凭证与成员会保留，不会被覆盖；已存在的门锁只刷新钥匙串与直连参数。恢复前会自动存一份快照（暂不支持在 App 内撤销）。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        // A5：导出走 FileDocument 落盘，导入走安全作用域 URL 读回。
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .plainText,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success(let url):
                AppToast.shared.show("已存到 " + url.lastPathComponent)
            case .failure(let e):
                errorLine = "存文件失败：" + e.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .json]
        ) { result in
            switch result {
            case .success(let url): readBackupFile(url)
            case .failure(let e): errorLine = "选文件失败：" + e.localizedDescription
            }
        }
        .itemConfirmationDialog("校验和不一致，仍然恢复？", item: $checkingChecksum, titleVisibility: .visible) { _ in
            Button("仍然恢复", role: .destructive) { Task { await performRestore() } }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("这份备份的内容与它自带的校验和不一致 —— 可能是导出后被改过，也可能是旧版本 App 的算法不同。确认来源可信再继续。")
        }
    }

    /// 导出文件名：锁名 + 日期，避免「文件」里出现一叠同名 backup.txt。
    /// 锁名是用户自由输入 —— `/ \ :` 这类字符会让 fileExporter 存盘失败，先消毒。
    private var backupFileName: String {
        let name = app.lock?.name ?? "阈值"
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = name.components(separatedBy: bad).joined(separator: "-")
        let day = When.dayKey(Int64(Date().timeIntervalSince1970))
        return "threshold-" + clean + "-" + day
    }

    /// A5：从系统文件选择器读回一段备份文本（安全作用域 URL 必须成对开关）。
    private func readBackupFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // 先查大小再读内容。String(contentsOf:) 会整份读进内存，
        // 而 parsePreview 的 32MB 闸发生在读完之后 —— 选了个超大文件就已经把内存吃满了。
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size <= BackupStudio.maxImportBytes else {
            errorLine = "这个文件 \(size / 1_048_576) MB，超过 \(BackupStudio.maxImportBytes / 1_048_576) MB 上限 —— 正常备份远小于此，请确认选对了文件。"
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorLine = "这个文件是空的 —— 可能不是备份文件。"
                return
            }
            importText = text
            importPassword = ""
            preview = nil
            importing = true
            errorLine = nil
            AppToast.shared.show("已读入 " + url.lastPathComponent)
        } catch {
            errorLine = "读文件失败：" + error.localizedDescription
        }
    }

    /// 校验和状态是人话，不是枚举名。
    /// （枚举直接插进 `Text` 会走 LocalizedStringKey 插值，SwiftUI 会警告它拿不到本地化描述。）
    private func checksumLabel(_ state: BackupStudio.ChecksumState) -> String {
        switch state {
        case .ok: return "一致"
        case .mismatch: return "不一致"
        case .absent: return "缺失"
        }
    }

    private func checksumTint(_ state: BackupStudio.ChecksumState) -> Color {
        switch state {
        case .ok: return T.C.ok
        case .mismatch: return T.C.danger
        case .absent: return T.C.ink3
        }
    }

    private func export() {
        errorLine = nil
        message = nil
        // 空壳里不生成备份。
        //
        // 设备/台账/成员会被数据层过滤成空，但 `collectAll` 直接从 `DB.get` 取的
        // `kf_passcode` / `kf_duress` **不判空壳** —— 信封里会带上两者真实的 PBKDF2 摘要。
        // 胁迫者拿走文件就能离线穷举 4–8 位数字，胁迫码当场失守。
        // 与「导入备份」同一道闸（`BackupStudioKit` 的 `guard !DB.isDecoy`）。
        guard !DB.isDecoy else {
            errorLine = "当前无法导出，请稍后再试。"
            return
        }
        guard passphrase.count >= 8 else {
            errorLine = "口令至少 8 位。没有口令就不生成备份。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let bundle = BackupKit.collectAll()
            let text = BackupCanonical.exportText(bundle)
            exported = try CryptoBox.encryptText(text, password: passphrase)
            Milestones.recordBackup()
            message = "备份已生成。"
        } catch {
            errorLine = error.localizedDescription
        }
    }

    private func doPreview() async {
        guard !busy else { return }
        errorLine = nil
        preview = nil
        busy = true
        defer { busy = false }
        do {
            let result = try BackupStudio.parsePreview(text: importText,
                                                       password: importPassword.isEmpty ? nil : importPassword)
            preview = result.preview
        } catch {
            errorLine = error.localizedDescription
        }
    }

    private func doRestore() async {
        guard !busy else { return }
        errorLine = nil
        // 空壳里不导入：`BackupStudio.restore` 自己也会拦，但它抛的是
        // 「当前模式下不能导入备份」—— 这句会让人追问「什么模式」。这里先用同一句中性话挡住。
        guard !DB.isDecoy else {
            errorLine = "当前无法恢复，请稍后再试。"
            return
        }
        // 这一页开头写着「导入先预览、再写盘」—— 那就真的**先预览**。
        // 原先「恢复」可以直接点：还没看清这份信封里是几把锁、哪几把会被跳过，
        // 数据就已经写进去了。回滚点只能救「写错了」，救不了「本来就不该写」。
        guard preview != nil else {
            errorLine = "先点「预览」看清这份备份里有什么，再恢复。"
            return
        }
        // 校验和不一致不硬拒（旧版本包算法不同），但必须二次确认 ——
        // Engine 只提供判据，确认动作在界面这一层。
        if let preview, BackupStudio.checksumNeedsAck(preview.checksum) {
            checkingChecksum = true
            return
        }
        await performRestore()
    }

    private func performRestore() async {
        guard !busy else { return }
        guard !DB.isDecoy else {
            errorLine = "当前无法恢复，请稍后再试。"
            return
        }
        guard preview != nil else {
            errorLine = "先点「预览」看清这份备份里有什么，再恢复。"
            return
        }
        errorLine = nil
        busy = true
        defer { busy = false }
        do {
            let result = try BackupStudio.parsePreview(text: importText,
                                                       password: importPassword.isEmpty ? nil : importPassword)
            let outcome = try BackupStudio.restore(result.bundle)
            preview = result.preview
            // 这里必须如实分开说：`overwritten` 统计的是**本机已有的门锁**
            // （钥匙串被刷新），不是"覆盖了你的凭证" —— 合并模式默认只增不删。
            var line = "已恢复：新增 \(outcome.imported) 条"
            if outcome.overwritten > 0 { line += " · \(outcome.overwritten) 把已有门锁的钥匙串已刷新" }
            if outcome.skipped > 0 { line += " · 跳过 \(outcome.skipped) 把锁" }
            if outcome.unlinkedOwners > 0 { line += " · \(outcome.unlinkedOwners) 条凭证找不到归属，已置空" }
            message = line
            await app.reload(refreshStatus: false)
        } catch {
            errorLine = error.localizedDescription
        }
    }
}

// A5：备份信封的 FileDocument —— fileExporter 落盘 / 文件 App 直接打开都要它。
// 与 ios27 的 BackupDoc 同一份实现：纯文本 UTF-8，无额外元数据。
struct EnvelopeDocument: FileDocument {
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
