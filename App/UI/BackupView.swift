// 备份与恢复 — 本地导出/导入 + 坚果云 WebDAV 加密同步 (与小程序信封互通)
// 覆盖性动作 (本地导入 / 云端恢复) 都必须二次确认; 云端恢复走 confirmationDialog,
// 因为要先下载解密拿到包, 才能告诉用户"会覆盖几台设备"。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var exportText = ""
    @State private var importText = ""
    /// 云盘账号与应用密码**只有本机存储这一份真相**：这里刻意不拍 `@State` 快照。
    /// 原先是 `@State … = DB.store.getString(...)` + `.onDisappear { persistCloudConfig() }`，
    /// 而本页与工坊 (`WebDAVStudioView`，经 NavigationLink/sheet 打开) 写的是同一对键 ——
    /// 在工坊里改完账号回到本页再关掉，`onDisappear` 就把**进页时那份旧快照**写回去，
    /// 刚改的凭据被静默覆盖 (第一百六十六批 §10.38)。读写穿透后没有"旧快照"这个东西。
    private var cloudAcct: String { DB.store.getString("kf_cloudcfg_acct") }
    private var cloudApp: String { DB.store.getString("kf_cloudcfg_app") }
    /// 加密口令**不入库**，所以它仍是 `@State`（每次输入、用完即弃）。
    /// 2026-10-26: 与另一页共用 BackupPassphrase（同一份 zklock-backup.enc 的加密口令）。
    /// 原来是各自一个 @State，用户在工作室传上去、到这一页恢复还要再输一遍，且没人说明是同一个口令。
    private var cloudPw: Binding<String> {
        Binding(get: { BackupPassphrase.current }, set: { BackupPassphrase.current = $0 })
    }
    /// 输入框直写本机存储：与工坊那页共用一份真相，谁改完另一页立刻读到新值。
    private var cloudAcctField: Binding<String> {
        Binding(get: { cloudAcct }, set: { DB.store.set("kf_cloudcfg_acct", $0) })
    }
    private var cloudAppField: Binding<String> {
        Binding(get: { cloudApp }, set: { DB.store.set("kf_cloudcfg_app", $0) })
    }
    @State private var busy = false
    /// 导出文件选择器（存到 iCloud 云盘 / 我的 iPhone）
    /// 与导入对称: 导入能选文件, 导出也该能存文件 —— 原来只有「复制/分享文本」这一条路,
    /// 而备份的正常去处就是 iCloud 云盘。
    @State private var showFileExporter = false
    /// 导入文件选择器（从 iCloud 云盘 / 我的 iPhone 选一份备份）
    @State private var showFilePicker = false
    /// 文件已读入但**还没**弹确认框 —— 选择器还在关闭过程中弹 UIAlertController 会被静默丢掉
    /// (两层模态套着)。所以先存这里, 等选择器真正收起后再问。
    @State private var pendingFileText: String?

    @State private var showWebDAV = false      // WebDAV 策略页，同上

private var cloudReady: Bool { !cloudAcct.isEmpty && !cloudApp.isEmpty && !BackupPassphrase.current.isEmpty }

    /// 内容是否已经嵌在外部导航容器里。2026-10-15 走查 §7.4-16: 这一页**自带 NavigationStack**,
    /// 有两个呈现点 —— 设置页的 sheet (要自己那层栏) 和设备页快捷格的 `quickDestination` push
    /// (那层栏已经在外面了)。push 那侧不传 true 就叠出两层导航栏。形状照 `AddPwdView` 的 embedded 抄,
    /// 那是本仓作者已有的解法。判据原文见本文件上方那条"自带 NavigationStack 的页只能走 sheet"。
    var embedded: Bool = false

    private var listContent: some View {
        List {
            exportSection
            importSection
            cloudSection
        }
        .navigationTitle("备份与恢复")
        .variantList()
        .dsScreenBackground()
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
    }

    var body: some View { vkBody.destined(.backup) }
    var vkBody: some View {
        // AnyView 擦平两分支类型差异 (与 AddPwdView 同一写法): 两支只差最外层那一只容器
        (embedded ? AnyView(listContent) : AnyView(NavigationStack { listContent }))
            // 2026-10-26 精简：待确认恢复包（pendingRestore）已删。
        .sheet(isPresented: $showWebDAV) { WebDAVStudioView() }
        // 方案 a: 文件选择器 —— 备份的正常去处是「iCloud 云盘 / 我的 iPhone」。
        // 与「粘贴文本」共用同一个解析入口 (doImportText → parsePreview), 不另写一套解析。
        .fileExporter(isPresented: $showFileExporter,
                      document: BackupDoc(text: exportText),
                      contentType: .json,
                      defaultFilename: backupFilename) { result in
            if case .success = result {
                Milestones.recordBackup()   // 落盘即算一次备份 (与生成备份文本同口径)
                app.showToast("已保存到文件")
            } else if case .failure(let e) = result {
                // 用户取消不报错 (NSUserCancelledError)
                if (e as NSError).code != NSUserCancelledError {
                    app.showToast("保存失败: " + e.localizedDescription)
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      // 不按扩展名筛: 备份可能是 .json / .txt / .enc (工作室导出的加密包)。
                      // 内容正确性由 parsePreview 把关 (解密 → 内容哈希 → schema), 不靠文件类型。
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
        // 选择器收起之后再弹确认框 (见 handleFileImport 里的说明)。
        .onChange(of: showFilePicker) { _, showing in
            guard !showing, let text = pendingFileText else { return }
            pendingFileText = nil
            importText = text
            confirmImport()
        }
    }


    // ---------- 全量备份 ----------
    private var exportSection: some View {
        Section("全量备份") {
            Text("导出全部门锁、钥匙、密码台账与家人档案为一整段文本 (含敏感密钥, 请妥善保管)。")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            BusyButton(title: "生成备份文本", systemImage: "doc.text", isBusy: false) {
                Milestones.recordBackup()   // 980 备份卫士
                exportText = BackupCanonical.exportText(BackupKit.collectAll())
            }
            // 822 从未备份的信封: 没有备份时这页最该说的不是"怎么导出"，而是"现在一个都没有"。
            // 文案不写"建议每周一次"这种本 App 没有依据的规范；给的是**已发生的事实**与下一步动作。
            if Milestones.lastBackupAt == nil {
                HStack(alignment: .top, spacing: DS.Space.s) {
                    Image(systemName: "envelope")
                        .font(.system(size: DS.Icon.md))
                        .foregroundStyle(DS.Palette.accentText)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("还没有备份").vkFont(.subheadline, weight: .medium)   // 822 还没有备份
                        Text("本机从未生成过备份文本，也没有上传成功记录。手机丢失或重装即不可恢复。")
                            .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if let at = Milestones.lastBackupAt {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("上次备份 " + at.formatted(date: .abbreviated, time: .shortened))   // 822 上次备份
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    // 822 建议备份时间: 读「备份工作室」的节奏档 (198 的 kf_bk_cadence, 本处为它的读方),
                    // 到期与否按上次备份时刻实算; 节奏为「仅手动」时不建议 —— 没有节奏就没有"到期"这一说。
                    // 2026-10-26 精简：备份节奏提醒已删（cadence 整套移除）。
                    // 193 体积预估: 本次预计 vs 上次实际 (备份工作室同样一行, 这里补全量导出入口的对照)
                }
            }
            if !exportText.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("共 \(exportText.count) 字符")
                        .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    Text(exportText)
                        .vkFont(.caption.monospaced())
                        .lineLimit(8).truncationMode(.tail)
                        .textSelection(.enabled) // 也可手动复制
                    ShareLink(item: exportText, preview: SharePreview("离线锁管家备份"))
                    // 主路径: 存到文件 (iCloud 云盘 / 本机) —— 与下面的导入对称
                    Button {
                        showFileExporter = true
                    } label: {
                        Label("存到 iCloud 云盘 / 本机", systemImage: "folder.badge.plus")
                            .frame(minHeight: DS.Hit.min)
                    }
                    .accessibilityHint("选 iCloud 云盘或我的 iPhone 里的位置保存备份文件")
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    // ---------- 导入恢复 ----------
    private var importSection: some View {
        Section("导入恢复") {
            Text("粘贴备份文本后导入。相同设备将覆盖, 其它设备保留 (门锁无需重置)。")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份文本", text: $importText, axis: .vertical)
                .vkFont(.caption.monospaced())
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy)
            Button {
                if let s = UIPasteboard.general.string, !s.isEmpty {
                    importText = s
                } else {
                    app.showToast("剪贴板是空的")
                }
            } label: {
                Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    .frame(minHeight: DS.Hit.min)
            }
            .disabled(busy || importText.isEmpty)
            // 从文件选择 (iCloud 云盘 / 我的 iPhone) —— 备份存在文件里时不必先复制再粘贴
            Button {
                showFilePicker = true
            } label: {
                Label("从文件选择", systemImage: "folder")
                    .frame(minHeight: DS.Hit.min)
            }
            .disabled(busy)
            Button("导入", role: .destructive) { confirmImport() } // 覆盖同名设备, 属破坏性动作
                .disabled(busy || importText.isEmpty)
        }
    }

    // ---------- 坚果云同步 ----------
    private var cloudSection: some View {
        Section("坚果云同步") {
            // 816 引导空态: 没配账号时先说"配了多什么"，再给**直达填写的入口**。
            // 三行只写这里真做得到的小事: 手动上传/手动恢复/先本机加密 —— 不写"自动同步"这种没实现的能力。
            // 原句要的"填服务器地址"确实在另一页 (WebDAVStudioView 改根路径)，所以这里给链接而不是假装一个输入框。
            if cloudAcct.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label("换手机或锁被重置时，云端那份是唯一的退路", systemImage: "arrow.left.arrow.right.circle")
                    Label("文件先在本机加密，服务器只拿到密文", systemImage: "lock.rectangle.stack")
                    Label("不配也能用：本页的文本导出与本地导入是完整可用的", systemImage: "square.and.arrow.down")
                    // 2026-10-15 走查: WebDAVStudioView 自带 NavigationStack, 而本页是 sheet ——
                    // push 进去就是内层栈套外层 (两层导航栏)。本页已有 `showWebDAV` 走 sheet 的先例,
                    // 这一条照同款改。
                    Button { showWebDAV = true } label: {
                        Text("服务器根路径默认内置坚果云，点这里可改")   // 816 服务器根路径默认内置
                            .vkFont(.caption2, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    .frame(minHeight: DS.Hit.min)
                }
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
            }
            TextField("坚果云账号", text: cloudAcctField)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy)
            SecureField("应用专属密码 (非登录密码)", text: cloudAppField)
                .disabled(busy)
            SecureField("加密口令 (不落盘)", text: cloudPw)
                .disabled(busy)
            BusyButton(title: "上传备份到坚果云", systemImage: "icloud.and.arrow.up", isBusy: busy && cloudMode == .push) {
                Task { await push() }
            }
            .disabled(!cloudReady)
            BusyButton(title: "从坚果云恢复", systemImage: "icloud.and.arrow.down", isBusy: busy && cloudMode == .pull) {
                Task { await pull() }
            }
            .disabled(!cloudReady)
            Text("账号与应用密码保存在本机 (可在坚果云网页撤销); 加密口令每次输入, 不落盘。")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum CloudMode { case push, pull }
    @State private var cloudMode: CloudMode = .push

    // ---------- 本地导入 ----------
    private func confirmImport() {
        guard !importText.isEmpty else { app.showToast("请先粘贴备份文本"); return }
        guard !busy else { return }
        // 2026-10-13 对抗式排查: 补一句**应用锁口令可能被替换**。
        // BackupKit.restoreAll 会把包内 globals.passcode 写回 kf_passcode (换机迁移要靠它),
        // 但"导入一份旧备份"同样会让应用锁口令**回滚到旧值** —— 抢到手机的人用旧口令就能进。
        // 這件事不能默默发生, 至少在破坏性确认里说清楚。
        confirmDestructive("导入备份",
                           "相同设备将被覆盖, 其它设备保留; 若备份里带应用锁口令, 本机口令会被替换成它。确定导入吗？",
                           confirmTitle: "导入") {
            doImport()
        }
    }
    private func doImport() {
        // 2026-10-13 对抗式排查: 原写直接 `JSONDecoder().decode(BackupBundle.self)` + restoreAll,
        // 把云端那套**口令层 + 453 内容哈希层**整个绕过:
        //   · 哈希不一致 (内容被改过) 的包在云端路径会被拦下 —— "内容哈希不一致 — 已拦下, 未写任何数据";
        //   · 本地粘贴导入却照写不疑。备份文件本身就是明文含 skey/pins 的全库快照,
        //     "能拿到文件就能改"完全在威胁模型之内。
        // 改成走 parsePreview 这**唯一**入口 (先解密 → 再校验哈希 → 再走升级链), 哈希不过就拦,
        // 与云端路径同一套判据。加密备份仍需口令 (本页只收明文粘贴, 与改动前一致)。
        do {
            // 2026-10-13 修 CI: `BackupStudioKit` 是**文件名**, 类型名是 `BackupStudio` (enum)。
            let (_, bundle) = try BackupStudio.parsePreview(text: importText, password: nil)
            let r = BackupKit.restoreAll(bundle)
            app.loadDevices()
            if bundle.globals?.appearance != nil { app.reloadAppearance() }   // 894 带外观段才刷, 免得白重建一次全树
            armMigrateWizard(r)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.showToast("导入完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
            importText = ""
        } catch {
            // 口令错误 / 内容被改过 (453) / 不是备份 —— 一律不写库
            app.showToast("导入被拦下: \(error.localizedDescription)")
        }
    }

    // 包3/idea 112: 换机恢复后立起验证向导 — 设备 Tab 逐锁点按验证连接, 全部通过后自动收起
    private func armMigrateWizard(_ r: (imported: Int, overwritten: Int)) {
        guard r.imported + r.overwritten > 0 else { return }
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        DB.store.set("kf_migrate_pending", ISO8601DateFormatter().string(from: Date()))
    }

    // ---------- 文件导入 (iCloud 云盘 / 我的 iPhone) ----------

    /// 导出文件名 —— 带日期, 多次备份不互相覆盖。
    private var backupFilename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        f.dateFormat = "yyyyMMdd-HHmm"
        return "锁管家备份-\(f.string(from: Date()))"
    }

    /// 文件选择器的结果处理。
    ///
    /// 要点:
    ///   · fileImporter 给的是**临时可访问 URL**, 必须 startAccessingSecurityScopedResource
    ///     否则 read 会失败 (这是 iOS 沙盒规则, 不是可选步骤)
    ///   · 读出来的文本走与「粘贴导入」**同一个入口** (parsePreview), 不另写一套解析
    ///   · 任何失败都给 toast, 不静默
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
                app.showToast("这个文件读不出文本内容 · 备份文件是文本格式")
                return
            }
            // 不在这个回调里直接弹确认框: 它发生在**系统文件选择器还在关闭**的过程中,
            // 而 confirmDestructive 要 present 一个 UIAlertController —— 上一层模态没消失前
            // 系统会把它丢掉, 用户看到的就是「选了文件, 界面没有任何反应」。
            // 先存起来, 由 onChange(showFilePicker) 在选择器收起后再问。
            pendingFileText = text
        case .failure(let error):
            // 用户取消不报错 (NSUserCancelledError)
            if (error as NSError).code != NSUserCancelledError {
                app.showToast("没能打开文件")
            }
        }
    }

    // ---------- 云端上传 ----------
    // ---------- 云端上传 ----------
    private func push() async {
        guard !busy else { return }
        guard cloudReady else { app.showToast("请填写账号/应用密码/加密口令"); return }
        busy = true
        cloudMode = .push
        defer { busy = false }
        do {
            let payload = BackupKit.collectAll()
            guard let data = try? JSONEncoder().encode(payload),
                  let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw NSError(domain: "backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "备份编码失败, 已中止上传"])
            }
            let envelope = try CryptoBox.encryptText(text, password: BackupPassphrase.current)
            try await CloudSync.push(acct: cloudAcct, app: cloudApp, envelope: envelope)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Milestones.recordBackup()   // 980 备份卫士
            app.showToast("上传成功")
        } catch { app.showToast(error.localizedDescription) }
    }

    // ---------- 云端恢复: 先下载解密, 再让用户确认覆盖, 最后才写盘 ----------
    private func pull() async {
        guard !busy else { return }
        guard cloudReady else { app.showToast("请填写账号/应用密码/加密口令"); return }
        busy = true
        cloudMode = .pull
        defer { busy = false }
        do {
            guard let envelope = try await CloudSync.download(acct: cloudAcct, app: cloudApp) else {
                app.showToast("云端暂无备份"); return
            }
            // 2026-10-14: 走 parsePreview —— 旧实现自己 decrypt+decode, 绕过了 453 内容哈希闸、
            // schema 上界闸与 upgradeChain (本地粘贴与工作室 WebDAV 都过它)。云端包同样不可信。
            let (_, bundle) = try BackupStudio.parsePreview(text: envelope, password: BackupPassphrase.current)
            // 不直接落盘: 交给 confirmationDialog, 用户确认后才覆盖本机
        } catch { app.showToast(error.localizedDescription) }
    }



    private func applyPendingRestore() {
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        if bundle.globals?.appearance != nil { app.reloadAppearance() }   // 894 带外观段才刷, 免得白重建一次全树
        armMigrateWizard(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        BackupPassphrase.clear()   // 2026-10-26: 改用共享口令容器后，清空走它的入口（原写 cloudPw = ""）
    }

}

/// fileExporter 要的文档类型 —— 备份是一段 UTF-8 文本, 用 `.json` 内容类型。
///
/// 用 FileDocument 而不是 Transferable: `.fileExporter(document:contentType:)` 这一形
/// 在 iOS 16+ 上是**同步可用**的, 而 Transferable 那一形要求文件已经落在磁盘上。
struct BackupDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}