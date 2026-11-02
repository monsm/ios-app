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
    /// 备份目录**读取失败**的原因（nil = 读取正常）。与"目录为空"是两件事：
    /// 前者要报错，后者是正常的首次状态。
    @State private var filesError: String?
    @State private var keepCount = 5
    @State private var password = ""
    @State private var outcome: String?
    @State private var busy = false
    /// 已确认过校验和不一致的那份**内容**的指纹（不是布尔）。
    /// 布尔一旦置真就永远为真 —— 用户换一份坏包也会被静默放行，保护随之失效。
    /// 记指纹 = 只对用户刚才看过并同意的那一份放行；内容一变就必须重新确认。
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
        }
        .background(V.C.bg.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("")
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
                // 读取失败与"没有备份"必须分开显示（前者要说原因，后者是正常的首次状态）。
                if let filesError {
                    VStatusLine(tone: .attention, text: filesError)
                } else if files.isEmpty {
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
                    // 预演就把"会被跳过的锁"报出来：否则用户看到"8 密码"、点确认后只回来 3 条，
                    // 会以为备份坏了（SEC-08 会整把锁跳过非法 skey/pin）。
                    if p.skippedLocks > 0 {
                        VValueRow(label: "将被跳过",
                                  value: "\(p.skippedLocks) 把（密钥格式非法，SEC-08 拒绝写入）")
                    }
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
                    // 三种状态三种颜色：一致=绿、不一致=红、还没基线=中性（不是错误）。
                    // 旧实现用二分支 `hasPrefix("一致") ? 绿 : 红`，把"还没有备份基线"也涂成红色 ——
                    // 一个纯状态被画成了故障。
                    Text(selfCheck).font(V.F.footnote)
                        .foregroundStyle(selfCheck.hasPrefix("一致") ? V.C.rewardGreen
                                         : (selfCheck.hasPrefix("还没有") ? V.C.text3 : V.C.pink))
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
        // 2026-11-01（Round 315）：**空壳模式必须返回空集**。
        // 本仓 SEC-03 的判据写得很清楚：「凭证工作室 / 备份工作室 / 记录工作室 这些直接读 DB 的页面
        // 必须据此返回空集，否则胁迫者能在空壳里看到并导出真实凭证」。前两个都做了，这里漏了 ——
        // 它读的是 Documents 目录（`FileManager` 直读，绕过了所有 `DB` 访问器），所以没有任何守卫。
        //
        // 后果不只是「看到文件名」：被胁迫者说「我这 App 里没东西」，界面上却列着十几份备份，伪装当场穿帮；
        // 更糟的是可以点「恢复」，用旧备份覆盖真实台账。
        if DB.isDecoy {
            files = []
            filesError = nil
            keepCount = 0
            return
        }
        let fm = FileManager.default
        // 2026-11-01：读取目录失败与"目录为空"必须区分开。
        // 旧实现 `?? []` 把失败当成空 —— 界面上就是"还没有本机备份"；
        // 而真实原因可能是沙箱/权限/目录损坏，用户会以为备份丢了（然后去重新生成，覆盖 keep 配额）。
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
            // SEC-02：备份包里是整库 skey/pins/ekey —— 不允许「留空口令 = 明文落盘」。
            // 旧实现默认明文，一次点击就把「家门万能钥匙」写成可被系统备份带走的文件。
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

    private func restoreFile(_ file: BackupFile) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let url = BackupStudio.dir.appendingPathComponent(file.name)
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try BackupStudio.parsePreview(text: text, password: password.isEmpty ? nil : password)
            // SEC-14：校验和对不上时**要求二次确认**。
            // 不硬拦的理由：本 App 旧版本导出的包用的是旧键序 canonical，FNV 必然对不上 ——
            // 硬拒绝等于把用户自己的合法备份挡在门外（"恢复不了"比"被截断包覆盖"更糟）。
            // 不提示也不行：那会让半截包静默覆盖真数据。二次确认同时满足两边。
            // 按**内容指纹**确认：只对用户刚看过并同意的那一份放行。
            // 用布尔会永久放行 —— 换一份坏包也不再提示，保护就失效了。
            let fp = BackupCanonical.fnv1a32Hex(text)
            if BackupStudio.checksumNeedsAck(parsed.preview.checksum), ackedChecksumFor != fp {
                ackedChecksumFor = fp
                outcome = "校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），也可能真被截断/改动过。确认要继续请再点一次恢复。"
                return
            }
            let r = try BackupStudio.restore(parsed.bundle)
            ackedChecksumFor = nil   // 一次性确认：恢复完作废，下一次重新判断
            // 跳过数同样要报（`restore` 一直返回它，这里此前只报新增/覆盖）。
            // 2026-11-01（Round 287）：状态色是按**文案前缀**决定的（`hasPrefix("已") ? 绿 : 粉`，全仓 10 处）。
            // 而「跳过了 N 把锁」「N 项归属找不到」都是**部分失败** —— 原来一律以「已恢复」开头 ⇒ 涂绿。
            // 改成部分失败时以「部分完成」开头：既保住可读性，又让颜色如实。
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

    /// 2026-11-01：原来 `try?` 吞掉删除结果，**无论成功失败都报"已删除"** ——
    /// 删除失败（文件被占用 / 目录只读）时界面说已删、`reloadFiles()` 之后文件又出现在列表里，
    /// 用户会以为"删了又自己回来了"。现在按真实结果报。
    private func deleteFile(_ file: BackupFile) {
        do {
            try FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name))
            outcome = "已删除 \(file.name)"
        } catch {
            outcome = "删除失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        reloadFiles()
    }

    private func pruneFiles() {
        let extra = files.dropFirst(max(keepCount, 1))
        guard !extra.isEmpty else { return }
        var failed = 0
        for file in extra {
            do { try FileManager.default.removeItem(at: BackupStudio.dir.appendingPathComponent(file.name)) }
            catch { failed += 1 }
        }
        reloadFiles()
        // 同上：失败分支不能以「已」开头 —— 否则「N 份删除失败」会被前缀规则涂成绿色。
        outcome = failed == 0 ? "已清理 \(extra.count) 份旧备份"
                              : "\(failed) 份删除失败（已清理 \(extra.count - failed) 份）"
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // 钉公历：否则系统历法切成佛历时文件名会变成 `25691101-…`（备份文件名要能被排序与人工识别）。
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: - 动作（WebDAV）

    private func saveDav() {
        DB.store.set("kf_bk_dav_url", davURL.trimmingCharacters(in: .whitespaces))
        DB.store.set("kf_bk_dav_user", davUser)
        DB.store.set("kf_bk_dav_path", davPath.isEmpty ? "zklock-backup.json" : davPath)
        // 2026-11-01（Round 257）：`SecretStore.set` 返回 Bool（钥匙串写入成功与否），
        // 原来用 `_ =` 把它丢掉，紧接着**无条件**报「配置已保存」—— 钥匙串写失败时密码其实没存下来，
        // 用户下次上传会以"没有密码"的形态失败，而界面一直说已保存。
        let pwOK = SecretStore.set(davPassword, for: "backup.webdav.password")
        davState = pwOK
            ? "成功：WebDAV 配置已保存"
            : "配置已保存，但应用密码没能写进钥匙串 —— 请重试；若一直失败，检查系统钥匙串是否可用"
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
        do {
            let plain = BackupCanonical.exportText(BackupKit.collectAll())
            // SEC-02：换机包同样必须加密（它会被复制到剪贴板，可能经通用剪贴板同步到别的设备）。
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
            // SEC-14：换机包同样走二次确认（理由见 restoreFile 里的说明）。
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
    @MainActor static func fingerprint() -> String {
        BackupCanonical.fnv1a32Hex(BackupCanonical.exportText(BackupKit.collectAll()))
    }
}

// MARK: - 极简 WebDAV 客户端（Basic Auth）

enum WebDAV {
    static func test(base: String, user: String, password: String) async throws -> String {
        // 2026-11-01（Round 235）：与 `upload` 同一个坑 —— `URL(string:)` 遇到空格/中文返回 nil。
        // 走 `URLComponents` 让它负责百分号编码（用户粘贴的地址里带空格并不罕见）。
        guard let comps = URLComponents(string: normalized(base)), let url = comps.url
        else { throw BLEErrorX.msg("WebDAV 地址不是合法 URL") }
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
        // 2026-11-01（Round 234）：原来用**字符串拼接** `base + "/" + path` 再 `URL(string:)` ——
        // 路径里一旦有空格或中文（备份文件名完全可能），`URL(string:)` 直接返回 nil，
        // 报出来的是「WebDAV 远端地址不是合法 URL」，而用户看着地址明明是对的。
        // 改用 URLComponents：`path` 接受未转义字符串，取 `.url` 时自动百分号编码。
        guard var comps = URLComponents(string: normalized(base)) else { throw BLEErrorX.msg("WebDAV 远端地址不是合法 URL") }
        let basePath = comps.path.hasSuffix("/") ? comps.path : comps.path + "/"
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        comps.path = basePath + cleanPath
        guard let url = comps.url else { throw BLEErrorX.msg("WebDAV 远端地址不是合法 URL") }
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

    /// SEC-20：只接受 https。旧实现允许 http:// —— 局域网下 WebDAV 账号与
    /// 完整备份（含 skey）会以明文过 Wi-Fi，同一网络的攻击者可直接读走。
    /// 例外只有本机回环（用户自建调试服务器），且仍会显示"明文"提示。
    private static func normalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("https://") { return t }
        if t.hasPrefix("http://") {
            let host = URL(string: t)?.host?.lowercased() ?? ""
            if host == "localhost" || host == "127.0.0.1" { return t }
            return "https://" + t.dropFirst("http://".count)
        }
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