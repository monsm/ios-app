// BackupStudioScreen.swift —— 备份工作室（WebDAV 配置 / 多份保留 / 换机迁移 / 自检）。
//
// 来源：原 App/Services/BackupStudioKit.swift（WebDAV 同步、多份保留、换机迁移、448 启动自检）
//   与 App/UI/BackupView.swift 的备份工作室段。
// 这屏干什么：在「备份与恢复」之外提供四件事 ——
//   ① 本机多份备份文件（可列出 / 恢复 / 删除 / 限制保留份数）；
//   ② WebDAV 地址与账号配置、连通性测试、把当前备份 PUT 上去；
//   ③ 换机迁移包的生成与导入（逐把锁可选合并 / 保留 / 跳过）；
//   ④ 数据自检（库体指纹对比上次备份基线）。
// 数据从哪来：BackupKit.collectAll + BackupCanonical + CryptoBox + BackupStudio.restore。
// 主动作：「生成一份本机备份」；WebDAV 与迁移都是次级动作。
import SwiftUI
import Foundation
import UIKit

struct BackupStudioScreen: View {
    @Environment(AppModel.self) private var app

    @State private var files: [BackupFile] = []
    @State private var keepCount = 5
    @State private var password = ""
    @State private var outcome: String?
    @State private var busy = false

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

    struct BackupFile: Identifiable {
        let name: String
        let size: Int
        let date: Date
        var id: String { name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                fileCard
                webdavCard
                migrateCard
                selfCheckCard
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("备份工作室")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadFiles() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("备份工作室")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("本机多份备份 · WebDAV · 换机迁移 · 数据自检")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    // MARK: - 多份保留

    private var fileCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "本机备份")
                Text("备份含门锁密钥，等同于家门钥匙。文件只留在本机 Documents，别发给别人。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VTextFieldRow(label: "备份口令（可留空 = 明文）", text: $password, placeholder: "至少 8 位", secure: true)
                VActionButton(title: busy ? "正在生成…" : "生成一份本机备份", systemImage: "externaldrive.badge.plus") {
                    Task { await makeBackup() }
                }
                .disabled(busy)
                VRowDivider()
                VValueRow(label: "保留份数", value: "\(keepCount) 份", note: "超过会自动删最旧的一份，避免备份把手机塞满。")
                HStack(spacing: V.S.gapS) {
                    ForEach([3, 5, 10, 20], id: \.self) { n in
                        Button { keepCount = n; DB.store.set("kf_bk_keep", n); pruneFiles() } label: {
                            VTag(text: "\(n) 份", tint: keepCount == n ? V.C.blue : V.C.text3, filled: keepCount == n)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                VRowDivider()
                if files.isEmpty {
                    Text("还没有本机备份文件。点上面「生成一份本机备份」—— 它会把锁 / 凭证 / 成员 / 设置打成一份可恢复的文件。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(files) { file in
                        fileRow(file)
                        VDivider()
                    }
                }
                if let outcome {
                    Text(outcome).font(V.F.footnote)
                        .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func fileRow(_ file: BackupFile) -> some View {
        HStack(spacing: V.S.gapS) {
            Image(systemName: "doc.zipper")
                .font(V.F.rowTitle)
                .foregroundStyle(V.C.text3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(file.name).font(V.F.rowDetail).foregroundStyle(V.C.text1).lineLimit(1)
                Text("\(byteText(file.size)) · \(file.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(V.F.micro).foregroundStyle(V.C.text3)
            }
            Spacer(minLength: 0)
            Button("恢复") { restoreFile(file) }
                .font(V.F.footnote).foregroundStyle(V.C.blue)
            Button("删除") { deleteFile(file) }
                .font(V.F.footnote).foregroundStyle(V.C.pink)
        }
        .frame(minHeight: V.List.rowMinHeight)
    }

    private func byteText(_ n: Int) -> String {
        if n >= 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576) }
        if n >= 1024 { return String(format: "%.0f KB", Double(n) / 1024) }
        return "\(n) B"
    }

    // MARK: - WebDAV

    private var webdavCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "WebDAV 同步")
                Text("填自己的 WebDAV 地址（如坚果云）。账号密码只存本机 Keychain / 偏好，不上传第三方。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VTextFieldRow(label: "服务器地址", text: $davURL, placeholder: "https://dav.example.com/remote.php/dav/files/me/")
                VTextFieldRow(label: "账号", text: $davUser, placeholder: "邮箱 / 用户名")
                VTextFieldRow(label: "应用密码", text: $davPassword, placeholder: "应用专属密码", secure: true)
                VTextFieldRow(label: "远端文件名", text: $davPath, placeholder: "zklock-backup.json")
                HStack(spacing: V.S.gapS) {
                    VOutlineButton(title: "保存配置", systemImage: "checkmark") { saveDav() }
                    VOutlineButton(title: "测试连接", systemImage: "antenna.radiowaves.left.and.right") {
                        Task { await testDav() }
                    }
                    .disabled(busy || davURL.isEmpty)
                }
                VActionButton(title: busy ? "上传中…" : "上传当前备份", systemImage: "icloud.and.arrow.up") {
                    Task { await uploadDav() }
                }
                .disabled(busy || davURL.isEmpty)
                if let davState {
                    Text(davState).font(V.F.footnote)
                        .foregroundStyle(davState.hasPrefix("成功") || davState.hasPrefix("连接正常") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 换机迁移

    private var migrateCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "换机迁移")
                Text("换机包 = 一份含全部锁与凭证的备份。旧手机生成 → 新手机粘贴导入；逐把锁可选「合并 / 保留本机 / 跳过」。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "生成换机包文本", systemImage: "arrow.left.arrow.right") {
                    Task { await makeMigration() }
                }
                .disabled(busy)
                VTextFieldRow(label: "粘贴换机包", text: $migrateText, placeholder: "从旧手机复制过来的备份文本", axisVertical: true)
                VOutlineButton(title: "预览换机包", systemImage: "doc.text.magnifyingglass") {
                    Task { await previewMigration() }
                }
                .disabled(migrateText.isEmpty || busy)
                if let p = migratePreview {
                    VRowDivider()
                    VValueRow(label: "来源", value: p.source, mono: false)
                    VValueRow(label: "锁", value: "\(p.macs.count) 把")
                    VValueRow(label: "凭证", value: "\(p.pwdCount) 密码 · \(p.fpCount) 指纹")
                    VValueRow(label: "成员", value: "\(p.memberCount) 位")
                    VValueRow(label: "校验和", value: checksumText(p.checksum))
                    ForEach(p.macs, id: \.self) { mac in
                        HStack(spacing: V.S.gapS) {
                            Text(LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: "")))
                                .font(V.F.rowDetail).foregroundStyle(V.C.text1).lineLimit(1)
                            Spacer(minLength: 0)
                            ForEach(Array([(key: "merge", label: "合并"), (key: "keep", label: "保留本机"), (key: "skip", label: "跳过")].enumerated()), id: \.offset) { pair in
                                let item = pair.element
                                Button { lockActs[mac] = item.key } label: {
                                    VTag(text: item.label, tint: (lockActs[mac] ?? "merge") == item.key ? V.C.blue : V.C.text3, filled: (lockActs[mac] ?? "merge") == item.key)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VActionButton(title: "导入换机包", systemImage: "square.and.arrow.down") {
                        Task { await runMigration() }
                    }
                    .disabled(busy)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 自检

    private var selfCheckCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "数据自检")
                Text("库体指纹 = 当前全部本机数据的 FNV1a32；与上次备份时的基线比对，能发现「备份之后数据坏了/少了」。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VValueRow(label: "当前指纹", value: SelfCheck.fingerprint())
                VValueRow(label: "上次备份基线", value: DB.store.getString("kf_bk_base", "尚未建立"))
                if let selfCheck {
                    Text(selfCheck).font(V.F.footnote)
                        .foregroundStyle(selfCheck.hasPrefix("一致") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: V.S.gapS) {
                    VOutlineButton(title: "立即自检", systemImage: "checkmark.shield") { runSelfCheck() }
                    VOutlineButton(title: "以当前数据重建基线", systemImage: "arrow.clockwise") { rebuildBaseline() }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 动作（多份备份）

    private func reloadFiles() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: BackupStudio.dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return BackupFile(name: url.lastPathComponent, size: size, date: date)
            }
            .sorted { $0.date > $1.date }
        keepCount = DB.store.getInt("kf_bk_keep", 5)
    }

    private func makeBackup() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            let text = password.isEmpty ? plain : try CryptoBox.encryptText(plain, password: password)
            let name = "backup-" + Self.stamp() + ".json"
            try Data(text.utf8).write(to: BackupStudio.dir.appendingPathComponent(name), options: .atomic)
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

    private func restoreFile(_ file: BackupFile) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let url = BackupStudio.dir.appendingPathComponent(file.name)
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try BackupStudio.parsePreview(text: text, password: password.isEmpty ? nil : password)
            let r = BackupStudio.restore(parsed.bundle)
            outcome = "已恢复 \(file.name)：新增 \(r.imported) 项，覆盖 \(r.overwritten) 项"
            Task { await app.reload(refreshStatus: false) }
        } catch {
            outcome = "恢复失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func deleteFile(_ file: BackupFile) {
        try? FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name))
        reloadFiles()
        outcome = "已删除 \(file.name)"
    }

    private func pruneFiles() {
        let extra = files.dropFirst(max(keepCount, 1))
        for file in extra { try? FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name)) }
        if !extra.isEmpty { reloadFiles() }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: - 动作（WebDAV）

    private func saveDav() {
        DB.store.set("kf_bk_dav_url", davURL.trimmingCharacters(in: .whitespaces))
        DB.store.set("kf_bk_dav_user", davUser)
        DB.store.set("kf_bk_dav_path", davPath.isEmpty ? "zklock-backup.json" : davPath)
        _ = SecretStore.set(davPassword, for: "backup.webdav.password")
        davState = "成功：WebDAV 配置已保存"
    }

    private func testDav() async {
        guard !busy else { return }
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
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let plain = BackupCanonical.exportText(BackupKit.collectAll())
            let text = password.isEmpty ? plain : try CryptoBox.encryptText(plain, password: password)
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
        do {
            let plain = BackupCanonical.exportText(BackupKit.collectAll())
            let text = password.isEmpty ? plain : try CryptoBox.encryptText(plain, password: password)
            UIPasteboard.general.string = text
            outcome = "换机包已复制到剪贴板（\(text.count) 字符）"
        } catch {
            outcome = "生成失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func previewMigration() async {
        do {
            let parsed = try BackupStudio.parsePreview(text: migrateText, password: password.isEmpty ? nil : password)
            migratePreview = parsed.preview
        } catch {
            outcome = "预览失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func runMigration() async {
        do {
            let parsed = try BackupStudio.parsePreview(text: migrateText, password: password.isEmpty ? nil : password)
            let r = BackupStudio.restore(parsed.bundle, lockActs: lockActs)
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

// MARK: - 库体指纹

enum SelfCheck {
    static func fingerprint() -> String {
        BackupCanonical.fnv1a32Hex(BackupCanonical.exportText(BackupKit.collectAll()))
    }
}

// MARK: - 极简 WebDAV 客户端（Basic Auth）

enum WebDAV {
    static func test(base: String, user: String, password: String) async throws -> String {
        guard let url = URL(string: normalized(base)) else { throw BLEErrorX.msg("WebDAV 地址不是合法 URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        if !user.isEmpty { req.setValue("Basic " + auth(user, password), forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BLEErrorX.msg("没有收到 HTTP 响应") }
        guard (200 ..< 300).contains(http.statusCode) || http.statusCode == 207 else {
            throw BLEErrorX.msg("HTTP \(http.statusCode) — 检查地址、账号与应用密码")
        }
        return "HTTP \(http.statusCode)"
    }

    static func upload(text: String, base: String, path: String, user: String, password: String) async throws -> String {
        let target = base.hasSuffix("/") ? base + path : base + "/" + path
        guard let url = URL(string: normalized(target)) else { throw BLEErrorX.msg("WebDAV 远端地址不是合法 URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !user.isEmpty { req.setValue("Basic " + auth(user, password), forHTTPHeaderField: "Authorization") }
        req.httpBody = Data(text.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BLEErrorX.msg("上传失败：HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return path
    }

    private static func normalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://" + t
    }

    private static func auth(_ user: String, _ password: String) -> String {
        Data((user + ":" + password).utf8).base64EncodedString()
    }
}

#Preview("BackupStudioScreen") {
    NavigationStack { BackupStudioScreen() }
        .environment(AppModel())
        .environment(Router())
}
