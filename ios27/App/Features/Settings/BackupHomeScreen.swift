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

//   ③ 2026-11-05（S5 归并 C）：备份工作室整页并入这里 —— WebDAV / 多份 / 迁移 / 自检
//      成为「工作室」四段；原工作室入口卡删除，路由由 Lead 改指本页。

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

    /// 恢复备份的后果说明（合并进备份页时漏掉的属性）。
    /// 内容与旧 BackupStudio 页的恢复确认一致：说清「只增不删」「口令可能回滚」「有回滚快照但无反向撤销」。
    private var restoreConsequence: String {
        "同名项会被覆盖，备份里没有的条目保持不动（只增不删）。本机密码可能被回滚成备份当时的那个；"
        + "导入前会自动写一个回滚快照（含明文密钥，保留最近 4 份），这是本机恢复前的唯一数据副本 —— "
        + "没有反向撤销按钮。"
    }



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
        return "备份文件含门锁密钥，拿到它的人不需要你的手机就能开你家门。别发聊天软件，别放共享文件夹。多份备份、WebDAV 上传与换机迁移都在这一页的工作室段。"
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
                studioFilesCard
                studioWebdavCard
                studioMigrateCard
                studioSelfCheckCard
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


    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(
                    icon: .ring(store.lastBackupAt == nil ? 0.02 : 1, store.lastBackupAt == nil ? V8.C.warn : V8.C.ok),
                    label: "上次备份",
                    value: store.lastBackupAt.map { TimeFormat.ago($0) } ?? "从未"
                )
                VChip2(icon: .ring(1, V8.C.accent), label: "门锁", value: "\(app.lock == nil ? 0 : 1) 把")
                VChip2(icon: .ring(1, V8.D.fingerprint), label: "凭证", value: "\(app.keys.count) 枚")
                VChip2(icon: .ring(1, V8.D.mobile), label: "成员", value: "\(app.members.count) 位")
                VChip2(icon: .glyph("doc.zipper"), label: "多份备份", value: "\(files.count) 份")
                VChip2(icon: .glyph("icloud"), label: "WebDAV", value: davURL.isEmpty ? "未配置" : "已配置")
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
            Text("备份工作室另有两条边界：备份文件不显示（目录绕过数据库访问器直读文件，不拦会把家门钥匙目录摊开）；生成、恢复、删除、上传与迁移全部停用。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapXS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }




    // MARK: - 工作室 · 状态（并入自 BackupStudioHomeScreen）


    private struct BackupItem: Identifiable {
        let name: String
        let size: Int
        let date: Date
        var id: String { name }
    }
    @State private var files: [BackupItem] = []
    /// 备份目录**读取失败**的原因（nil = 读取正常）。与「目录为空」是两件事。
    @State private var filesError: String?
    @State private var keepCount = 5
    @State private var password = ""
    @State private var outcome: String?
    @State private var busy = false
    /// 恢复与删除备份都是**不可逆**动作，先弹确认。
    @State private var restoreTarget: BackupItem?
    @State private var deleteTarget: BackupItem?
    /// 已确认过校验和不一致的那份**内容**的指纹（不是布尔）。
    @State private var studioAckedFor: String?

    // WebDAV
    @State private var davURL = DB.store.getString("kf_bk_dav_url")
    @State private var davUser = DB.store.getString("kf_bk_dav_user")
    @State private var davPassword = SecretStore.get("backup.webdav.password") ?? ""
    @State private var davPath = DB.store.getString("kf_bk_dav_path", "zklock-backup.json")
    @State private var davState: String?

    // 换机迁移
    @State private var migrateText = ""
    @State private var migratePreview: BackupStudio.Preview?
    @State private var lockActs: [String: String] = [:]

    // 自检
    @State private var selfCheck: String?


    // MARK: - 本机多份备份

    private var studioFilesCard: some View {
        VCard2 {
            // 2026-11-05（对抗审查 · 设计冗余）：本页本来有两个「生成备份」入口，都叫备份、
            // 各有一个口令框、各说一遍「忘了就废」。改成一眼能分清的两种交付形态：
            // 这里是**留在本机的文件**（有份数上限），下面对应的是**可复制的文本**。
            // 2026-11-05（值级重复）：trailing 原来是「N 份」，而顶部芯片「多份备份」已经显示同一个数。
            VCardHead(eyebrow: "备份文件", statement: "留在本机 · 含门锁密钥")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("备份文件只留在本机 Documents，别发给别人 —— 它等同于家门钥匙。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("备份口令（必填，至少 8 位）", text: $password)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            Button { Task { await makeBackup() } } label: {
                Text(busy ? "正在生成…" : "生成一份本机备份")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(V8PressStyle())
            .disabled(busy)
            .opacity(busy ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            Text("保留份数：超过会自动删最旧的一份，避免备份把手机塞满。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: V8.S.gapChip) {
                ForEach([3, 5, 10, 20], id: \.self) { n in
                    keepChip(n)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            if files.isEmpty {
                Text("还没有本机备份文件。点上面「生成一份本机备份」—— 它会把锁 / 凭证 / 成员 / 设置打成一份可恢复的文件。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { pair in
                        if pair.offset > 0 { VDotRule() }
                        fileRow(pair.element)
                    }
                }
            }
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if trialOn {
                Text(TrialCopy.blocked("恢复与导入备份", note: "生成与导出仍可用"))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fileRow(_ file: BackupItem) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            HStack(spacing: V8.S.gapS) {
                Image(systemName: "doc.zipper")
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(file.name)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        .lineLimit(1)
                    Text("\(byteText(file.size)) · \(file.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: V8.S.gapL) {
                Button("恢复") { restoreTarget = file }
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.accent)
                    .frame(minHeight: V8.H.min)
                Button("删除") { deleteTarget = file }
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.danger)
                    .frame(minHeight: V8.H.min)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: V8.H.min)
    }

    private func keepChip(_ n: Int) -> some View {
        let on = keepCount == n
        return Button {
            keepCount = n
            DB.store.set("kf_bk_keep", n)
            pruneFiles()
        } label: {
            Text("\(n) 份")
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel("保留 \(n) 份")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func byteText(_ n: Int) -> String {
        if n >= 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        if n >= 1024 { return String(format: "%.0f KB", Double(n) / 1024) }
        return "\(n) B"
    }

    // MARK: - WebDAV

    private var studioWebdavCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "WebDAV 同步", statement: "只做单向上传")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("填自己的 WebDAV 地址（如坚果云）。账号密码只存本机钥匙串 / 偏好，不上传第三方。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: V8.S.gapM) {
                davField("服务器地址", text: $davURL, placeholder: "https://dav.example.com/remote.php/dav/files/me/")
                davField("账号", text: $davUser, placeholder: "邮箱 / 用户名")
                davSecureField("应用密码", text: $davPassword, placeholder: "应用专属密码")
                davField("远端文件名", text: $davPath, placeholder: "zklock-backup.json")
            }
            .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapL) {
                Button { saveDav() } label: {
                    Text("保存配置")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(V8PressStyle())
                Button { Task { await testDav() } } label: {
                    Text("测试连接")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(V8PressStyle())
                .disabled(busy || davURL.isEmpty)
                .opacity((busy || davURL.isEmpty) ? 0.45 : 1)
                Spacer(minLength: 0)
            }
            Button { Task { await uploadDav() } } label: {
                Text(busy ? "上传中…" : "上传当前备份")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(V8PressStyle())
            .disabled(busy || davURL.isEmpty)
            .opacity((busy || davURL.isEmpty) ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
            Text("只做单向上传（覆盖同一个远端文件）：不列远端备份、也不删远端文件 —— 那两项需要 PROPFIND 解析，本版没有实现。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if let davState {
                Text(davState)
                    .font(V8.T.footnote)
                    .foregroundStyle(davState.hasPrefix("成功") || davState.hasPrefix("连接正常") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func davField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text(label)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            TextField(placeholder, text: text)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
        }
    }

    private func davSecureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Text(label)
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
            SecureField(placeholder, text: text)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
        }
    }

    // MARK: - 换机迁移

    private var studioMigrateCard: some View {
        VCard2 {
            VCardHead(eyebrow: "换机迁移", statement: "旧手机生成 → 新手机粘贴导入")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("换机包 = 一份含全部锁与凭证的备份；逐把锁可选「合并 / 保留本机 / 跳过」。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await makeMigration() } } label: {
                Text("生成换机包文本")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.accent)
                    .frame(minHeight: V8.H.min)
            }
            .buttonStyle(V8PressStyle())
            .disabled(busy)
            .opacity(busy ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            TextField("从旧手机复制过来的备份文本", text: $migrateText, axis: .vertical)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .lineLimit(2...6)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .padding(.vertical, V8.S.gapS)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            Button { Task { await previewMigration() } } label: {
                Text("预览换机包")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.accent)
                    .frame(minHeight: V8.H.min)
            }
            .buttonStyle(V8PressStyle())
            .disabled(migrateText.isEmpty || busy)
            .opacity((migrateText.isEmpty || busy) ? 0.45 : 1)
            .padding(.top, V8.S.gapS)
            if let p = migratePreview {
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VStack(spacing: 0) {
                    VDataRow(tag: "来源", tagTint: V8.C.ink4, title: p.source, value: "")
                    VDotRule()
                    VDataRow(tag: "锁", tagTint: V8.C.ink4, title: "将导入", value: "\(p.macs.count) 把")
                    VDotRule()
                    VDataRow(tag: "凭证", tagTint: V8.C.ink4, title: "密码 / 指纹", value: "\(p.pwdCount) / \(p.fpCount)")
                    VDotRule()
                    VDataRow(tag: "成员", tagTint: V8.C.ink4, title: "成员数", value: "\(p.memberCount) 位")
                    VDotRule()
                    VDataRow(tag: "校验", tagTint: V8.C.ink4, title: "校验和", value: checksumText(p.checksum))
                    if p.skippedLocks > 0 {
                        VDotRule()
                        VDataRow(tag: "跳过", tagTint: V8.C.warn, title: "密钥格式非法", value: "\(p.skippedLocks) 把")
                    }
                }
                .padding(.top, V8.S.gapS)
                VStack(spacing: V8.S.gapS) {
                    ForEach(p.macs, id: \.self) { mac in
                        HStack(spacing: V8.S.gapS) {
                            Text(LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: "")))
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.ink1)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            ForEach(Array([(key: "merge", label: "合并"), (key: "keep", label: "保留本机"), (key: "skip", label: "跳过")].enumerated()), id: \.offset) { pair in
                                actChip(pair.element.label, key: pair.element.key, mac: mac)
                            }
                        }
                    }
                }
                .padding(.top, V8.S.gapM)
                Button { Task { await runMigration() } } label: {
                    Text("导入换机包")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .disabled(busy || trialOn)
                .opacity((busy || trialOn) ? 0.45 : 1)
                .padding(.top, V8.S.gapM)
                Text("导入前会自动写一个回滚快照（含明文密钥，保留最近 4 份），这是本机恢复前的唯一数据副本。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actChip(_ title: String, key: String, mac: String) -> some View {
        let on = (lockActs[mac] ?? "merge") == key
        return Button {
            lockActs[mac] = key
        } label: {
            Text(title)
                .font(V8.T.micro)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink3)
                .padding(.horizontal, V8.S.gapS)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(title + " " + mac)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 数据自检

    private var studioSelfCheckCard: some View {
        VCard2 {
            VCardHead(eyebrow: "数据自检", statement: "库体指纹对比备份基线")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("库体指纹 = 当前全部本机数据的 FNV1a32；与上次备份时的基线比对，能发现「备份之后数据坏了 / 少了」。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                VDataRow(tag: "当前", tagTint: V8.C.ink4, title: "当前指纹", value: SelfCheck.fingerprint())
                VDotRule()
                VDataRow(tag: "基线", tagTint: V8.C.ink4, title: "上次备份基线", value: DB.store.getString("kf_bk_base", "尚未建立"))
            }
            .padding(.top, V8.S.gapS)
            if let selfCheck {
                Text(selfCheck)
                    .font(V8.T.footnote)
                    .foregroundStyle(selfCheck.hasPrefix("一致") ? V8.C.ok : (selfCheck.hasPrefix("还没有") ? V8.C.ink3 : V8.C.danger))
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: V8.S.gapL) {
                Button { runSelfCheck() } label: {
                    Text("立即自检")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(V8PressStyle())
                Button { rebuildBaseline() } label: {
                    Text("以当前数据重建基线")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(V8PressStyle())
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
        }
    }


    private var studioChipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(files.isEmpty ? 0.02 : 1, files.isEmpty ? V8.C.ink4 : V8.C.ok),
                       label: "本机备份", value: "\(files.count) 份")
                VChip2(icon: .glyph("tray.full"), label: "保留上限", value: "\(keepCount) 份")
                VChip2(icon: .glyph("icloud"), label: "WebDAV", value: davURL.isEmpty ? "未配置" : "已配置")
                VChip2(icon: .glyph("checkmark.shield"), label: "自检", value: selfCheck == nil ? "未跑" : "已跑")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }


    // MARK: - 空壳

    // MARK: - 卡 1 全量备份

    private var exportCard: some View {
        VCard2 {
            // 与上面的「备份文件」互补：这一个产出**可复制的文本**（发给自己的另一台设备用）。
            VCardHead(eyebrow: "备份文本", statement: "可复制 · 用于换机或留档", trailing: "加密")
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
            // 2026-11-05（去冗余）：整句「忘记密码 = 永久作废」在上面「备份文件」卡已说过一次。
            // 这里只留一句短提示，不再复述整段 —— 同一页两段同样的警告只是噪声。
            Text("口令丢了就打不开这份文本；两个口令框各自独立，别混用。")
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
            .buttonStyle(V8PressStyle())
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
                    .buttonStyle(V8PressStyle())
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
                    .buttonStyle(V8PressStyle())
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
                .buttonStyle(V8PressStyle())
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
                .buttonStyle(V8PressStyle())
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
            .buttonStyle(V8PressStyle())
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




    // MARK: - 工作室 · 动作（并入自 BackupStudioHomeScreen，逻辑原样）


    // MARK: - 动作（多份备份）

    private func reloadFiles() {
        // 空壳模式必须返回空集：备份目录是 FileManager 直读，绕过了所有 DB 访问器。
        if DB.isDecoy {
            files = []
            filesError = nil
            keepCount = 0
            return
        }
        let fm = FileManager.default
        // 读取目录失败与「目录为空」必须区分开。
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: BackupStudio.dir,
                                              includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            filesError = nil
        } catch {
            urls = []
            filesError = "读取备份目录失败：" + error.localizedDescription
        }
        files = urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return BackupItem(name: url.lastPathComponent, size: size, date: date)
            }
            .sorted { $0.date > $1.date }
        keepCount = DB.store.getInt("kf_bk_keep", 5)
    }

    private func makeBackup() async {
        guard !decoyed else {
            outcome = DecoyCopy.blocked("生成备份")
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            // SEC-02：备份包里是整库 skey/pins/ekey —— 不允许「留空口令 = 明文落盘」。
            guard !password.isEmpty else {
                outcome = "未设置备份口令 · 已拒绝写入明文备份。请先在上方设一个口令再生成（换机迁移同样需要它）。"
                AppToast.shared.show("未设口令，未生成备份", tone: .warn)
                return
            }
            let text = try CryptoBox.encryptText(plain, password: password)
            let name = "backup-" + Self.stamp() + ".json"
            // SEC-10：含密钥的文件必须「设备锁屏即不可读」。
            try Data(text.utf8).write(to: BackupStudio.dir.appendingPathComponent(name),
                                      options: [.atomic, .completeFileProtection])
            DB.store.set("kf_bk_base", SelfCheck.fingerprint())
            Milestones.recordBackup()
            reloadFiles()
            pruneFiles()
            outcome = "已生成本机备份 · \(name)"
            AppToast.shared.show("已生成备份文件", tone: .ok)
        } catch {
            outcome = "生成失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func restoreFile(_ file: BackupItem) {
        guard !decoyed else {
            outcome = DecoyCopy.blocked("恢复备份")
            return
        }
        guard !trialOn else {
            outcome = TrialCopy.refused("导入备份会改写本机台账")
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let url = BackupStudio.dir.appendingPathComponent(file.name)
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try BackupStudio.parsePreview(text: text, password: password.isEmpty ? nil : password)
            // SEC-14：校验和对不上时要求二次确认。按内容指纹确认：只对用户刚看过并同意的那一份放行。
            let fp = BackupCanonical.fnv1a32Hex(text)
            if BackupStudio.checksumNeedsAck(parsed.preview.checksum), studioAckedFor != fp {
                studioAckedFor = fp
                outcome = "校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），也可能真被截断/改动过。确认要继续请再点一次恢复。"
                return
            }
            let r = try BackupStudio.restore(parsed.bundle)
            studioAckedFor = nil   // 一次性确认：恢复完作废，下一次重新判断
            let partial = r.skipped > 0 || r.unlinkedOwners > 0
            var summary = partial ? "部分完成 · \(file.name)：" : "已恢复 \(file.name)："
            summary += "新增 \(r.imported) 项，覆盖 \(r.overwritten) 项"
            if r.skipped > 0 { summary += "，跳过 \(r.skipped) 把锁（密钥格式非法）" }
            if r.unlinkedOwners > 0 { summary += "；\(r.unlinkedOwners) 项凭证的归属在本机找不到（已置为未归属）" }
            outcome = summary
            Task { await app.reload(refreshStatus: false) }
        } catch {
            outcome = "恢复失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 删除失败也要如实报（旧实现 try? 吞结果，无论成功失败都报「已删除」）。
    private func deleteFile(_ file: BackupItem) {
        guard !decoyed else {
            outcome = DecoyCopy.blocked("删除备份")
            return
        }
        do {
            try FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name))
            outcome = "已删除 \(file.name)"
        } catch {
            outcome = "删除失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        reloadFiles()
    }

    private func pruneFiles() {
        guard !decoyed else { return }
        let extra = files.dropFirst(max(keepCount, 1))
        guard !extra.isEmpty else { return }
        var failed = 0
        for file in extra {
            do { try FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name)) }
            catch { failed += 1 }
        }
        reloadFiles()
        // 失败分支不能以「已」开头 —— 否则会被前缀规则涂成绿色。
        outcome = failed == 0 ? "已清理 \(extra.count) 份旧备份"
                              : "\(failed) 份删除失败（已清理 \(extra.count - failed) 份）"
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // 钉公历：否则系统历法切成佛历时文件名会变成 25691101-…。
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
    // MARK: - 动作（WebDAV）

    private func saveDav() {
        guard !decoyed else {
            davState = DecoyCopy.blocked("保存 WebDAV 配置")
            return
        }
        DB.store.set("kf_bk_dav_url", davURL.trimmingCharacters(in: .whitespaces))
        DB.store.set("kf_bk_dav_user", davUser)
        DB.store.set("kf_bk_dav_path", davPath.isEmpty ? "zklock-backup.json" : davPath)
        // SecretStore.set 返回 Bool（钥匙串写入成功与否），不能丢掉。
        let pwOK = SecretStore.set(davPassword, for: "backup.webdav.password")
        davState = pwOK
            ? "成功：WebDAV 配置已保存"
            : "配置已保存，但应用密码没能写进钥匙串 —— 请重试；若一直失败，检查系统钥匙串是否可用"
    }

    private func testDav() async {
        guard !decoyed, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let msg = try await WebDAV.test(base: davURL, user: davUser, password: davPassword)
            davState = "连接正常 · " + msg
        } catch {
            davState = "连接失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func uploadDav() async {
        guard !decoyed, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let plain = BackupCanonical.exportText(BackupKit.collectAll())
            // SEC-02：上云的包必须加密 —— 走明文等于把母钥发给 WebDAV 服务器。
            guard !password.isEmpty else { throw BLEErrorX.msg("请先设备份口令：上云的备份必须加密") }
            let text = try CryptoBox.encryptText(plain, password: password)
            let msg = try await WebDAV.upload(text: text, base: davURL, path: davPath, user: davUser, password: davPassword)
            DB.store.set("kf_bk_base", SelfCheck.fingerprint())
            Milestones.recordBackup()
            davState = "成功：已上传 → \(msg)"
        } catch {
            davState = "上传失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 动作（迁移）

    private func makeMigration() async {
        guard !decoyed else {
            outcome = DecoyCopy.blocked("生成换机包")
            return
        }
        do {
            let plain = BackupCanonical.exportText(BackupKit.collectAll())
            // SEC-02：换机包同样必须加密（会被复制到剪贴板，可能经通用剪贴板同步到别的设备）。
            guard !password.isEmpty else {
                outcome = "未设口令 · 已拒绝生成明文换机包"
                return
            }
            let text = try CryptoBox.encryptText(plain, password: password)
            Clip.set(text)
            outcome = "换机包已复制到剪贴板（\(text.count) 字符）"
        } catch {
            outcome = "生成失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func previewMigration() async {
        guard !decoyed else { return }
        do {
            let parsed = try BackupStudio.parsePreview(text: migrateText, password: password.isEmpty ? nil : password)
            migratePreview = parsed.preview
        } catch {
            outcome = "预览失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func runMigration() async {
        guard !decoyed else {
            outcome = DecoyCopy.blocked("导入换机包")
            return
        }
        guard !trialOn else {
            outcome = TrialCopy.refused("导入备份会改写本机台账")
            return
        }
        do {
            let parsed = try BackupStudio.parsePreview(text: migrateText, password: password.isEmpty ? nil : password)
            // SEC-14：换机包同样走二次确认。
            let fp = BackupCanonical.fnv1a32Hex(migrateText)
            if BackupStudio.checksumNeedsAck(parsed.preview.checksum), studioAckedFor != fp {
                studioAckedFor = fp
                outcome = "换机包校验和对不上：可能是旧版本生成（属正常），也可能被截断/改动过。确认要导入请再点一次。"
                return
            }
            let r = try BackupStudio.restore(parsed.bundle, lockActs: lockActs)
            outcome = "迁移完成：新增 \(r.imported) 项，覆盖 \(r.overwritten) 项，跳过 \(r.skipped) 把锁"
            migrateText = ""
            migratePreview = nil
            await app.reload(refreshStatus: false)
        } catch {
            outcome = "迁移失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 自检

    private func runSelfCheck() {
        let base = DB.store.getString("kf_bk_base")
        if base.isEmpty {
            selfCheck = "还没有备份基线 —— 先「生成一份本机备份」。"
        } else if base == SelfCheck.fingerprint() {
            selfCheck = "一致：当前数据与上次备份时相同。"
        } else {
            selfCheck = "不一致：上次备份后本机数据有变化。若刚改过凭证属正常；若没改过，请查存储是否损坏。"
        }
    }

    private func rebuildBaseline() {
        guard !decoyed else { return }
        DB.store.set("kf_bk_base", SelfCheck.fingerprint())
        selfCheck = "已重建基线。"
    }

    private func checksumText(_ state: BackupStudio.ChecksumState) -> String {
        switch state {
        case .ok: return "校验通过"
        case .mismatch: return "校验失败"
        case .absent: return "无校验和"
        }
    }

}

