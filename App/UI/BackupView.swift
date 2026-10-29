// 备份与恢复 — 本地导出/导入 + 坚果云 WebDAV 加密同步 (与小程序信封互通)
// 覆盖性动作 (本地导入 / 云端恢复) 都必须二次确认; 云端恢复走 confirmationDialog,
// 因为要先下载解密拿到包, 才能告诉用户"会覆盖几台设备"。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var exportText = ""
    @State private var encryptExport = false      // 2026-10-27: 可选加密主备份
    @State private var exportPw = ""
    /// 2026-10-28 修复：导入侧原来**没有口令输入框**，两处 parsePreview 都传 `password: nil` ——
    /// 而导出侧（:98 的 SecureField）能加密。于是用户一旦勾了「备份密码」，那份备份
    /// **永远导不回来**（decryptAny 会抛「此备份带口令」）。
    @State private var importPw = ""
    @State private var importText = ""
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


    /// 内容是否已经嵌在外部导航容器里。2026-10-15 走查 §7.4-16: 这一页**自带 NavigationStack**,
    /// 有两个呈现点 —— 设置页的 sheet (要自己那层栏) 和设备页快捷格的 `quickDestination` push
    /// (那层栏已经在外面了)。push 那侧不传 true 就叠出两层导航栏。形状照 `AddPwdView` 的 embedded 抄,
    /// 那是本仓作者已有的解法。判据原文见本文件上方那条"自带 NavigationStack 的页只能走 sheet"。
    var embedded: Bool = false

    private var listContent: some View {
        List {
            exportSection
            importSection
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
            // 2026-10-27 审核修复：主备份含明文 skey/pin/密码，任何人都能用它造开锁指令。
            Text("⚠ 此文件含**明文门锁密钥**（skey / pin / 密码）—— 任何人拿到它就能开你家门，不需要你的手机。请勿通过微信/QQ 发送，不要放在共享文件夹或公开网盘。")
                .vkFont(.caption).foregroundStyle(DS.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            Text("导出全部门锁、钥匙、密码台账与家人档案为一整段文本。")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-10-27 审核：主备份默认明文（含 skey）。给出可选加密 —— 用已有 CryptoBox
            // （PBKDF2-HMAC-SHA256 6 万轮 + AES-128-CBC + HMAC），与「351 凭证合包」同一套。
            // ⚠ 加密后忘记密码 = 备份永久作废，所以默认关闭、要用户主动勾。
            VariantToggle("加密备份（需设密码，忘记则备份作废）", isOn: $encryptExport)
                .vkFont(.footnote)
            if encryptExport {
                SecureField("备份密码", text: $exportPw)
                    .textContentType(.newPassword)
                    .vkFont(.footnote)
                if exportPw.count > 0, exportPw.count < 8 {
                    Text("至少 8 位")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                }
            }
            // 2026-10-28 修复（**安全级**）：原来 `.count < 8` 只显示一行提示，按钮照样能按 ——
            // 空密码/1 位密码都会被 `CryptoBox.encryptText` 当成合法口令，产出一个
            // 「看起来加密、实际谁都能解」的备份。现在按钮直接禁用，函数里再 guard 一次。
            // 另外 `Milestones.recordBackup()` 原来在函数**开头** —— 加密失败也会记一次「上次备份」，
            // 于是「上次备份于 X」会指向一个从未生成的备份。移到成功之后。
            BusyButton(title: "生成备份文本", systemImage: "doc.text", isBusy: false,
                       disabled: encryptExport && exportPw.count < 8) {
                let plain = BackupCanonical.exportText(BackupKit.collectAll())
                if encryptExport {
                    guard exportPw.count >= 8 else {
                        app.showToast("加密备份至少要 8 位密码")
                        return
                    }
                    exportText = (try? CryptoBox.encryptText(plain, password: exportPw)) ?? ""
                    if exportText.isEmpty {
                        app.showToast("加密失败 — 请检查密码后重试")
                        return   // 失败不记「上次备份」
                    }
                } else {
                    exportText = plain
                }
                Milestones.recordBackup()   // 980 备份卫士（只在真正生成成功后记一次）
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
            Text("粘贴备份文本后导入。导入是**合并**（只增不删）—— 本机已有的凭证会保留，同名冲突取本机。若想整表回滚到备份状态，请先手动清空该锁台账再导入。门锁本身无需重置。")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-10-28 补：加密备份需要口令才能解开（导出侧能加密，导入侧原先没有入口）
            SecureField("备份密码（导出时设过的才需要填）", text: $importPw)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy)
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
            // 2026-10-28 修复：原为 .disabled(busy || importText.isEmpty) —— **importText 为空时禁用**，
            // 而「从剪贴板粘贴」恰恰是 importText 为空时才需要按的那一枚。
            // 结果：想粘贴的人按不到，只有先手打几个字才解锁。改成只看 busy。
            .disabled(busy)
            // 从文件选择 (iCloud 云盘 / 我的 iPhone) —— 备份存在文件里时不必先复制再粘贴
            Button {
                showFilePicker = true
            } label: {
                Label("从文件选择", systemImage: "folder")
                    .frame(minHeight: DS.Hit.min)
            }
            .disabled(busy)
            Button("导入", role: .destructive) { confirmImport() } // 整表替换同名设备的台账, 属破坏性动作
                .disabled(busy || importText.isEmpty)
        }
    }

    // 2026-10-27 六轮精简：坚果云同步整节已删（WebDAV 一族移除）。


    // ---------- 本地导入 ----------
    private func confirmImport() {
        guard !importText.isEmpty else { app.showToast("请先粘贴备份文本"); return }
        guard !busy else { return }
        // 2026-10-27 审核修复 (AUDIT-D D-55)：**先解析出预览再确认**。
        // 原先确认框只说「台账会被整表替换」，用户看不到"将影响哪几把锁、多少条凭证"，
        // 就点了确认 —— 那不是知情同意，是盲签。
        // 现在先 parsePreview（它本身就是导入的必经入口：解密 → 校验哈希 → 升级链），
        // 把 macs / pwdCount / fpCount 摆进确认文案，再让用户点。
        let pv: BackupStudio.Preview
        do {
            let (p, _) = try BackupStudio.parsePreview(text: importText, password: importPw.isEmpty ? nil : importPw)
            pv = p
        } catch {
            app.showToast("导入被拦下: \(error.localizedDescription)")
            return
        }

        let lockList = pv.macs.isEmpty ? "（包内无设备）" : pv.macs.joined(separator: "、")
        // 2026-10-13 对抗式排查: 补一句**应用锁口令可能被替换** ——
        // 包内 globals.passcode 会写回 kf_passcode（换机迁移要靠它），
        // 而"导入一份旧备份"同样会让应用锁口令**回滚到旧值**。
        let detail = """
        这份备份包含 \(pv.macs.count) 把锁、\(pv.pwdCount) 条密码、\(pv.fpCount) 枚指纹。
        受影响的锁：\(lockList)

        导入会**合并**（只增不删）—— 本机已有的凭证会保留；同名冲突取本机。
        若备份里带应用锁口令，本机口令会被替换成它（可能回滚到旧值）。
        """
        confirmDestructive("导入备份", detail, confirmTitle: "导入") {
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
            let (_, bundle) = try BackupStudio.parsePreview(text: importText, password: importPw.isEmpty ? nil : importPw)
            // 2026-10-27 审核修复 (AUDIT-C F1)：改用 `BackupStudio.restore` —— **合并导入**。
            // 原先走 `BackupKit.restoreAll`，它对同设备台账是 `DB.saveLedger` **整表替换**，
            // 于是界面承诺「其它设备保留」而本机在备份之后新加的凭证会丢 —— 正是
            // `BackupStudioKit:297-298` 注释里描述的那个 bug。修复版一直写在隔壁（带 merge/keep/skip、
            // 冲突裁决、421 回滚点），但**零调用**。现在接上。
            // 默认行为 merge = 只增不删；冲突项默认取本机（conflictTakeBackup 为空）。
            let r = BackupStudio.restore(bundle, makeSnapshot: true)
            app.loadDevices()
            if bundle.globals?.appearance != nil { app.reloadAppearance() }   // 894 带外观段才刷, 免得白重建一次全树
            armMigrateWizard(r)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.showToast("导入完成: 新增 \(r.imported), 合并 \(r.overwritten)" + (r.skipped > 0 ? ", 跳过 \(r.skipped)" : ""))
            importText = ""
        } catch {
            // 口令错误 / 内容被改过 (453) / 不是备份 —— 一律不写库
            app.showToast("导入被拦下: \(error.localizedDescription)")
        }
    }

    // 包3/idea 112: 换机恢复后立起验证向导 — 设备 Tab 逐锁点按验证连接, 全部通过后自动收起
    private func armMigrateWizard(_ r: (imported: Int, overwritten: Int, skipped: Int)) {
        guard r.imported + r.overwritten > 0 else { return }
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        DB.store.set("kf_migrate_pending", DF.iso().string(from: Date()))
    }

    // ---------- 文件导入 (iCloud 云盘 / 我的 iPhone) ----------

    /// 导出文件名 —— 带日期, 多次备份不互相覆盖。
    private var backupFilename: String {
        let f = DF.cached("yyyyMMdd-HHmm")
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

    // ---------- 云端恢复: 先下载解密, 再让用户确认覆盖, 最后才写盘 ----------



    // 2026-10-26 精简：applyPendingRestore 已删 —— 它读的 pendingRestore 随「待确认恢复包」一起移除。

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
    // 【协议要求 2026-10-29】FileDocument 协议要求的方法 —— 由系统在保存时调用，不是死代码
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}