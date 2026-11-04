// BackupHomeScreen.swift —— 备份与恢复（V8 设计语言）
//
// 与 BackupScreen 的能力对齐：全量加密备份（含危险说明 / 将备份内容计数 / 口令 / 生成 / 复制 / 存文件）、
// 从备份文本恢复（预演摘要 / 校验和二次确认 / 当前本机密码验证 / 合并只增不删）、备份工作室入口。
// 只改渲染层：生成仍走 BackupKit.collectAll → BackupCanonical.exportText → CryptoBox.encryptText，
// 恢复仍走 BackupStudio.parsePreview → BackupStudio.restore，落盘键仍是 kf_bk_base 与 Milestones。
//
// 两处刻意差异：
//   ① 空壳模式下整页只读：旧页在空壳里仍能生成 / 恢复 —— 生成会把空壳过滤后的空数据写成「备份」并
//      覆盖 kf_bk_base 基线，恢复则会整表改写真实台账（引擎虽已拦恢复，界面也不该给出入口）。
//   ② 导出与恢复的错误分开显示：旧页共用一个 restoreError，导出失败会显示在恢复卡里，指错方向。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupHomeScreen: View {
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
    /// 这份内容是否已知校验和不一致（在已有的确认对话框里如实告知，不额外加一步）。
    @State private var importChecksumMismatch = false
    /// 已按内容指纹确认过校验和不一致的那一份（只用一次，恢复后作废）。
    @State private var ackedChecksumFor: String?
    @State private var showRestoreConfirm = false
    /// 选文件后先解析一次得到的预演摘要（凭证条数 / 会被跳过的锁数）。
    @State private var importPreviewNote = ""
    /// SEC-08：恢复会改写本机密码摘要，所以要先验当前本机密码。
    @State private var currentPasscode = ""
    @State private var restoreDone: (added: Int, merged: Int, skipped: Int, unlinked: Int)?
    /// 恢复被拦下的原因。不写「失败了」三个字，写清是哪一道闸拦的。
    @State private var restoreError: String?
    /// 导出侧自己的错误（旧页把它塞进恢复卡，指错方向）。
    @State private var exportError: String?
    /// 系统文件选择器：导出到「文件 / iCloud 云盘」，或从文件导入。
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc: BackupDoc?

    private var decoyed: Bool { DB.isDecoy }
    private var trialOn: Bool { app.trialGuard }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下备份只读" }
        guard let at = store.lastBackupAt else { return "本机从未生成过备份" }
        return "本机数据已有备份 · " + TimeFormat.dayShort(at) + " " + TimeDisplay.clock(at)
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。备份与恢复在这一屏都不执行 —— 退出空壳后再来。"
        }
        if store.lastBackupAt == nil {
            return "手机丢失或重装即不可恢复。先设一个备份密码，再生成第一份加密备份。"
        }
        return "备份文件含门锁密钥，拿到它的人不需要你的手机就能开你家门。别发聊天软件，别放共享文件夹。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else {
                studioCard
                exportCard
                importCard
                if trialOn { trialCard }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .plainText,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success(let url):
                AppToast.shared.show("已存到 " + url.lastPathComponent, tone: .ok)
            case .failure(let e):
                exportError = "存文件失败：" + e.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .json]
        ) { result in
            switch result {
            case .success(let url): readBackupFile(url)
            case .failure(let e): restoreError = "选文件失败：" + e.localizedDescription
            }
        }
        .v8Confirm(
            isPresented: $showRestoreConfirm,
            title: "恢复这份备份？",
            consequence: restoreConsequence,
            confirmTitle: "恢复（合并，只增不删）",
            isDestructive: true
        ) {
            runImport()
        }
    }

    /// 确认对话框的后果说明：先报「这次会写进多少」，再说合并语义、密码回滚与快照。
    private var restoreConsequence: String {
        var text = importPreviewNote
        if importChecksumMismatch {
            text += "这份备份的校验和对不上。可能是本 App 旧版本导出的包（键序不同，属正常），也可能真的被截断或改动过。\n\n"
        }
        text += "导入是合并：本机已有的凭证会保留，同名冲突取本机。若备份里带本机密码摘要，本机密码会被替换成它（可能回滚到旧值）。恢复前会自动写一份回滚快照（明文整库，留最近四份）到本机 —— 恢复本身没有反向撤销按钮。"
        return text
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(
                    icon: .ring(store.lastBackupAt == nil ? 0.02 : 1, store.lastBackupAt == nil ? V8.C.warn : V8.C.ok),
                    label: "上次备份",
                    value: store.lastBackupAt.map { TimeFormat.ago($0) } ?? "从未"
                )
                VChip2(icon: .ring(1, V8.C.accent), label: "门锁", value: "\(app.lock == nil ? 0 : 1) 把")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(app.keys.count) 枚")
                VChip2(icon: .ring(1, V8.D.mobile), label: "成员", value: "\(app.members.count) 位")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "备份与恢复", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这一屏既不生成也不恢复备份 —— 生成会把空壳过滤后的空数据当成「全量备份」并覆盖自检基线；恢复则会整表改写真实台账。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 0 备份工作室入口

    private var studioCard: some View {
        VCard2 {
            VCardHead(eyebrow: "备份工作室", statement: "多份备份与换机迁移")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("本机多份备份文件、WebDAV 同步、换机迁移包与数据自检都在工作室里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "打开备份工作室", detail: "WebDAV / 多份 / 迁移 / 自检") {
                router.request(.dest(.backupStudio))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 1 全量备份

    private var exportCard: some View {
        VCard2 {
            VCardHead(eyebrow: "全量备份", statement: "加密是唯一路径", trailing: "加密")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(alignment: .top, spacing: V8.S.gapS) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(V8.T.chipValue)
                    .foregroundStyle(V8.C.danger)
                    .accessibilityHidden(true)
                Text("备份文件含门锁密钥（skey / pin / 密码）。口令一旦泄露，文件就等于明文钥匙 —— 拿到它的人不需要你的手机就能开你家门。别发聊天软件，别放共享文件夹。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "门锁", tagTint: V8.C.ink4, title: "\(app.lock == nil ? 0 : 1)", value: "", unit: "把")
                VDotRule()
                VDataRow(tag: "凭证", tagTint: V8.D.fingerprint, title: "\(app.keys.count)", value: "", unit: "枚")
                VDotRule()
                VDataRow(tag: "成员", tagTint: V8.D.mobile, title: "\(app.members.count)", value: "", unit: "位")
                VDotRule()
                VDataRow(tag: "记录缓存", tagTint: V8.C.ink4, title: "\(app.entries.count)", value: "", unit: "条（不进包）")
            }
            .padding(.top, V8.S.gapS)
            Text("成员数含已归档 —— 归档成员及其名下凭证也会进备份。家页的「成员」只数在册。记录的手动归属认领只存在这台手机上，不进备份包 —— 换机恢复后这些记录会回到未归属，需要重新认一次。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.top, V8.S.gapM)
            SecureField("备份密码（至少 8 位）", text: $exportPassword)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .textContentType(.newPassword)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .accessibilityLabel("备份密码")
                .padding(.top, V8.S.gapM)
            if !exportPassword.isEmpty, exportPassword.count < 8 {
                Text("至少 8 位 —— 否则加密形同虚设")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
            }
            Text("忘记密码 = 这份备份永久作废。请把密码记在安全的地方，或另存一份到密码管理器。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                generate()
            } label: {
                Text(exporting ? "正在生成…" : "生成备份")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(exportPassword.count < 8 || exporting)
            .opacity((exportPassword.count < 8 || exporting) ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
            .accessibilityLabel("生成备份")
            if let exportError {
                VFailure(what: "生成备份没有完成", why: exportError, next: "检查备份密码后重试；本机数据没有被改动。")
                    .padding(.top, V8.S.gapM)
            }
            if !exportText.isEmpty {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Text("已生成")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                Text("\(exportText.count) 字符")
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .monospacedDigit()
                    .padding(.top, V8.S.gapXS)
                Text(exportText)
                    .font(V8.T.footnote.monospaced())
                    .foregroundStyle(V8.C.ink2)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .captureShield("这里是一份可开门的备份\n屏幕正在被录制或截图，已遮挡")
                    .padding(.top, V8.S.gapS)
                HStack(spacing: V8.S.gapS) {
                    Button {
                        Clip.set(exportText)
                    } label: {
                        Text("复制备份文本")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .overlay(
                                RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                    .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制备份文本")
                    Button {
                        exportDoc = BackupDoc(text: exportText)
                        showExporter = true
                    } label: {
                        Text("存到文件")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .overlay(
                                RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                    .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("存到文件")
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 卡 2 恢复

    private var importCard: some View {
        VCard2 {
            VCardHead(eyebrow: "恢复", statement: importText.isEmpty ? "还没有备份文本" : "已就绪，可预演")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if importing {
                VBusy(text: "正在解密并校验备份 · 不要离开")
                    .padding(.top, V8.S.gapM)
            }
            if let restoreError {
                VFailure(what: "恢复没有完成", why: restoreError, next: "按上面的提示处理后重试；本机数据没有被改写。")
                    .padding(.top, V8.S.gapM)
            }
            if let r = restoreDone {
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Text("恢复结果：新增 \(r.added) 项，合并 \(r.merged) 项"
                     + (r.skipped > 0 ? "，跳过 \(r.skipped) 把锁（密钥格式非法）" : "")
                     + (r.unlinked > 0 ? "；\(r.unlinked) 项凭证的归属在本机找不到（已置为未归属，可在凭证页重新指派）" : ""))
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("粘贴备份文本。导入是合并（只增不删）—— 本机已有的凭证会保留，同名冲突取本机。门锁本身无需重置。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份文本", text: $importText, axis: .vertical)
                .font(V8.T.footnote.monospaced())
                .foregroundStyle(V8.C.ink1)
                .lineLimit(3 ... 6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .accessibilityLabel("备份文本")
                .padding(.top, V8.S.gapS)
            SecureField("备份密码（导出时设过密码的才需要填）", text: $importPassword)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .accessibilityLabel("备份密码")
                .padding(.top, V8.S.gapS)
            if DB.hasPasscode() {
                SecureField("当前本机密码（导入会改写它，需先验证）", text: $currentPasscode)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .keyboardType(.numberPad)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                    .accessibilityLabel("当前本机密码")
                    .padding(.top, V8.S.gapS)
            }
            HStack(spacing: V8.S.gapS) {
                Button {
                    showImporter = true
                } label: {
                    Text("从文件选择")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从文件选择")
                Button {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        importText = s
                    }
                } label: {
                    Text("从剪贴板粘贴")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .overlay(
                            RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从剪贴板粘贴")
            }
            .padding(.top, V8.S.gapS)
            Button {
                // 点开的这一刻就知道校验和状态（checksumState 不需要口令，只解 JSON）：
                // 明文包能判出来，加密包返回 .absent（那由口令层负责，不归这里判）。
                importChecksumMismatch = (BackupStudio.checksumState(importText) == .mismatch)
                // 预演摘要也在这里算：这是唯一能同时覆盖「从文件选」与「粘贴」两条入口的位置。
                importPreviewNote = BackupHomeScreen.previewNote(text: importText, password: importPassword)
                showRestoreConfirm = true
            } label: {
                Text("恢复这份备份")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                    )
            }
            .buttonStyle(.plain)
            .disabled(importText.isEmpty || importing || trialOn)
            .opacity((importText.isEmpty || importing || trialOn) ? 0.4 : 1)
            .padding(.top, V8.S.gapS)
            .accessibilityLabel("恢复这份备份")
            if importText.isEmpty {
                Text("还没有备份文本。下一步：在上面点「生成备份」，再回来把文本粘到这里 —— 或者在换机时把上一条手机上的备份文本复制过来。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "导入被拦、导出放行")
            Text("只读试验模式拦的是下发到门锁的写命令与导入备份。导出是读本机数据，不在拦截范围内 —— 这里如实说明，不假装整页不可用。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func generate() {
        guard !exporting else { return }
        guard !DB.isDecoy else {
            exportError = "空壳模式下不生成备份 —— 空壳会把真实数据过滤成空集，生成出来的是一份空包。"
            return
        }
        exporting = true
        exportError = nil
        defer { exporting = false }
        do {
            // 真链路：collectAll（全部 kf_* 表）→ canonical（与小程序互通）→ 加密信封。
            // SEC-02：备份包里是整库 skey/pins/ekey —— 不允许「没设密码 = 明文」。
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            guard !exportPassword.isEmpty else {
                exportError = "请先设一个备份密码：这份备份包含能开门的密钥，不允许以明文生成。"
                return
            }
            exportText = try CryptoBox.encryptText(plain, password: exportPassword)
            // 980：只有真正生成成功才记一次备份（失败不记）。
            Milestones.recordBackup()
            // 与工作室的两条导出链（本地文件 / WebDAV）同口径：更新自检基线，避免假警报。
            DB.store.set("kf_bk_base", SelfCheck.fingerprint())
        } catch {
            exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        // SEC-30：先查大小再读内容。String(contentsOf:) 会整份读进内存，
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
            AppToast.shared.show("已读入 " + url.lastPathComponent, tone: .ok)
        } catch {
            restoreError = "读文件失败：" + error.localizedDescription
        }
    }

    /// 预演摘要：把「这次会写进多少」变成一句人话，供确认对话框开头展示。
    /// 解析失败返回空串（预演只是提前告知，不该阻断 —— 真正的错误由 runImport 报）。
    private static func previewNote(text: String, password: String) -> String {
        guard !text.isEmpty,
              let p = try? BackupStudio.parsePreview(text: text, password: password.isEmpty ? nil : password) else { return "" }
        // pwdCount / fpCount 只统计会被真正写入的锁（BackupStudioKit.parsePreview 的 willSkip 过滤）。
        var note = "这份备份里能被写入的有 \(p.preview.pwdCount) 条密码 / \(p.preview.fpCount) 枚指纹。\n\n"
        if p.preview.skippedLocks > 0 {
            note += "另有 \(p.preview.skippedLocks) 把锁的密钥格式非法，会整把跳过 —— 它们的凭证不计入上面的数字，也不会写进本机。\n\n"
        }
        return note
    }

    private func runImport() {
        guard !importText.isEmpty, !importing else { return }
        guard !DB.isDecoy else {
            restoreError = "空壳模式下不能导入备份 —— 导入会整表改写真实台账。"
            return
        }
        // SEC-08：恢复会改写本机密码摘要 —— 必须先用当前本机密码确认是本人。
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
                // SEC-14：校验和对不上不硬拦（旧版本导出的包本来就算不出同一个 FNV），
                // 但也不能静默继续 —— 按内容指纹要求再确认一次（内容一变就重新问）。
                let fp = BackupCanonical.fnv1a32Hex(importText)
                if BackupStudio.checksumNeedsAck(parsed.preview.checksum), ackedChecksumFor != fp {
                    ackedChecksumFor = fp
                    restoreError = "这份备份的校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），也可能真被截断或改动过。确认要继续请再点一次「恢复这份备份」。"
                    return
                }
                importChecksumMismatch = false
                ackedChecksumFor = nil   // 一次性：这次恢复完就作废，下次重新判断
                let r = try BackupStudio.restore(parsed.bundle)
                restoreDone = (added: r.imported, merged: r.overwritten, skipped: r.skipped, unlinked: r.unlinkedOwners)
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
