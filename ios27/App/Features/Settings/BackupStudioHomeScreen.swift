// BackupStudioHomeScreen.swift —— 备份工作室（V8 设计语言）
//
// 与 BackupStudioScreen 的能力对齐：本机多份备份（列出 / 恢复 / 删除 / 限制保留份数）、
// WebDAV 地址与账号配置、连通性测试、把当前备份上传、换机迁移包的生成与导入（逐把锁可选）、
// 数据自检（库体指纹对比上次备份基线）。
// 只改渲染层：加密仍走 CryptoBox.encryptText，恢复仍走 BackupStudio.restore，
// 自检仍走 SelfCheck.fingerprint（沿用同文件的既有实现），WebDAV 仍走 WebDAV.test / upload。
//
// 与旧页的刻意差异：
//   ① 空壳模式整页只读：文件列表置空之外，生成 / 恢复 / 删除 / 上传 / 迁移全部拒绝 ——
//      否则会让胁迫者用一份空档案覆盖真实备份。
//   ② 只读试验模式把「导入 / 恢复」标成不可用：BackupStudio.restore 入口会拒绝写台账。
import SwiftUI
import Foundation
import UIKit

struct BackupStudioHomeScreen: View {
    @Environment(AppModel.self) private var app

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
    @State private var ackedChecksumFor: String?

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

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示备份" }
        if files.isEmpty { return "还没有本机备份文件" }
        return "本机 \(files.count) 份备份 · 保留上限 \(keepCount) 份"
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏数据，不改动数据。备份文件不显示，生成、恢复、上传与迁移全部停用。" }
        return "本机多份备份 · WebDAV · 换机迁移 · 数据自检。备份含门锁密钥，等同于家门钥匙。"
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
                if let filesError {
                    VFailure(
                        what: "读取备份目录失败",
                        why: filesError,
                        next: "确认系统存储空间可用；重启 App 后再试。现在生成的备份仍会照常写入。"
                    )
                }
                fileCard
                webdavCard
                migrateCard
                selfCheckCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadFiles() }
        .v8Confirm(
            isPresented: Binding(
                get: { restoreTarget != nil },
                set: { if !$0 { restoreTarget = nil } }
            ),
            title: "恢复这份备份？",
            consequence: "「\(restoreTarget?.name ?? "")」里的锁与凭证会合并进当前台账：同名项被覆盖，不存在的项新增；当前台账里备份中没有的条目不会被删除。这个动作不能撤销。",
            confirmTitle: "恢复",
            isDestructive: true
        ) {
            if let file = restoreTarget {
                restoreTarget = nil
                restoreFile(file)
            }
        }
        .v8Confirm(
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            title: "删除这份备份文件？",
            consequence: "「\(deleteTarget?.name ?? "")」会从本机删除且不可恢复。如果这是唯一一份备份，删掉就没有可回滚的副本了。",
            confirmTitle: "删除",
            isDestructive: true
        ) {
            if let file = deleteTarget {
                deleteTarget = nil
                deleteFile(file)
            }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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

    // MARK: - 本机多份备份

    private var fileCard: some View {
        VCard2 {
            VCardHead(eyebrow: "本机备份", statement: "备份含门锁密钥", trailing: "\(files.count) 份")
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
            .buttonStyle(.plain)
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
            if readOnly {
                Text("只读试验模式已开启：恢复与导入备份会被拦下（生成与导出仍可用）。到「设置 → 安全」关掉再试。")
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
        .buttonStyle(.plain)
        .accessibilityLabel("保留 \(n) 份")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func byteText(_ n: Int) -> String {
        if n >= 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        if n >= 1024 { return String(format: "%.0f KB", Double(n) / 1024) }
        return "\(n) B"
    }

    // MARK: - WebDAV

    private var webdavCard: some View {
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
                .buttonStyle(.plain)
                Button { Task { await testDav() } } label: {
                    Text("测试连接")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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

    private var migrateCard: some View {
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
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .disabled(busy || readOnly)
                .opacity((busy || readOnly) ? 0.45 : 1)
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
        .buttonStyle(.plain)
        .accessibilityLabel(title + " " + mac)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 数据自检

    private var selfCheckCard: some View {
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
                .buttonStyle(.plain)
                Button { rebuildBaseline() } label: {
                    Text("以当前数据重建基线")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.accent)
                        .frame(minHeight: V8.H.min)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "备份工作室", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，备份文件不显示，生成、恢复、删除、上传与迁移全部停用 —— 备份目录是绕过数据库访问器直读文件的，不拦就会把整份家门钥匙目录摊开。")
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
            outcome = "空壳模式下不生成备份 —— 先退出空壳。"
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
            outcome = "空壳模式下不恢复备份 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            outcome = "只读试验模式已开启：导入备份会改写本机台账，已拒绝。请先到「安全」页关闭它。"
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
            if BackupStudio.checksumNeedsAck(parsed.preview.checksum), ackedChecksumFor != fp {
                ackedChecksumFor = fp
                outcome = "校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），也可能真被截断/改动过。确认要继续请再点一次恢复。"
                return
            }
            let r = try BackupStudio.restore(parsed.bundle)
            ackedChecksumFor = nil   // 一次性确认：恢复完作废，下一次重新判断
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
            outcome = "空壳模式下不删除备份 —— 先退出空壳。"
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
            davState = "空壳模式下不保存 WebDAV 配置 —— 先退出空壳。"
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
            outcome = "空壳模式下不生成换机包 —— 先退出空壳。"
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
            outcome = "空壳模式下不导入换机包 —— 先退出空壳。"
            return
        }
        guard !readOnly else {
            outcome = "只读试验模式已开启：导入备份会改写本机台账，已拒绝。请先到「安全」页关闭它。"
            return
        }
        do {
            let parsed = try BackupStudio.parsePreview(text: migrateText, password: password.isEmpty ? nil : password)
            // SEC-14：换机包同样走二次确认。
            let fp = BackupCanonical.fnv1a32Hex(migrateText)
            if BackupStudio.checksumNeedsAck(parsed.preview.checksum), ackedChecksumFor != fp {
                ackedChecksumFor = fp
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
