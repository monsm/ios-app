// 备份与恢复 — 本地导出/导入 + 坚果云 WebDAV 加密同步 (与小程序信封互通)
// 覆盖性动作 (本地导入 / 云端恢复) 都必须二次确认; 云端恢复走 confirmationDialog,
// 因为要先下载解密拿到包, 才能告诉用户"会覆盖几台设备"。
import SwiftUI
import UIKit

struct BackupView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var exportText = ""
    @State private var importText = ""
    @State private var cloudAcct = DB.store.getString("kf_cloudcfg_acct")
    @State private var cloudApp = DB.store.getString("kf_cloudcfg_app")
    @State private var cloudPw = ""
    @State private var busy = false
    /// 云端已下载但尚未经用户确认的备份包 (nil = 无待确认的恢复)
    @State private var pendingRestore: BackupBundle?

        @State private var showStudio = false

private var cloudReady: Bool { !cloudAcct.isEmpty && !cloudApp.isEmpty && !cloudPw.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                exportSection
                importSection
                cloudSection
                studioSection
            }
            .navigationTitle("备份与恢复")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
        .confirmationDialog("从云端恢复", isPresented: pendingRestoreBinding, titleVisibility: .visible) {
            Button("覆盖本机 \(DB.keychains().count) 台设备", role: .destructive) { applyPendingRestore() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("云端备份里包含 \(pendingRestore?.devices.count ?? 0) 台门锁。恢复后同名设备会被云端数据覆盖，本机现有改动将丢失。")
        }
        .sheet(isPresented: $showStudio) { BackupStudioView() }
        // 账号与应用密码属本机配置, 离开页面即落盘, 避免失败路径白填一次
        .onDisappear { persistCloudConfig() }
    }

    // pendingRestore != nil 即为"待确认", 确认/取消后都要清空以防重复触发
    private var pendingRestoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } })
    }

    // ---------- 全量备份 ----------
    private var exportSection: some View {
        Section("全量备份") {
            Text("导出全部门锁、钥匙、密码台账与家人档案为一整段文本 (含敏感密钥, 请妥善保管)。")
                .font(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            BusyButton(title: "生成备份文本", systemImage: "doc.text", isBusy: false) {
                Milestones.recordBackup()   // 980 备份卫士
                exportText = BackupCanonical.exportText(BackupKit.collectAll())
                app.evaluateAchievements()
            }
            if !exportText.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("共 \(exportText.count) 字符")
                        .font(.caption).foregroundStyle(DS.Palette.textSub)
                    Text(exportText)
                        .font(.caption.monospaced())
                        .lineLimit(8).truncationMode(.tail)
                        .textSelection(.enabled) // 也可手动复制
                    ShareLink(item: exportText, preview: SharePreview("离线锁管家备份"))
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    // ---------- 导入恢复 ----------
    private var importSection: some View {
        Section("导入恢复") {
            Text("粘贴备份文本后导入。相同设备将覆盖, 其它设备保留 (门锁无需重置)。")
                .font(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份文本", text: $importText, axis: .vertical)
                .font(.caption.monospaced())
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
            Button("导入", role: .destructive) { confirmImport() } // 覆盖同名设备, 属破坏性动作
                .disabled(busy || importText.isEmpty)
        }
    }

    // ---------- 坚果云同步 ----------
    private var cloudSection: some View {
        Section("坚果云同步") {
            TextField("坚果云账号", text: $cloudAcct)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy)
            SecureField("应用专属密码 (非登录密码)", text: $cloudApp)
                .disabled(busy)
            SecureField("加密口令 (不落盘)", text: $cloudPw)
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
                .font(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum CloudMode { case push, pull }
    @State private var cloudMode: CloudMode = .push

    private func persistCloudConfig() {
        guard !cloudAcct.isEmpty else { return }
        DB.store.set("kf_cloudcfg_acct", cloudAcct)
        if !cloudApp.isEmpty { DB.store.set("kf_cloudcfg_app", cloudApp) }
    }

    // ---------- 本地导入 ----------
    private func confirmImport() {
        guard !importText.isEmpty else { app.showToast("请先粘贴备份文本"); return }
        guard !busy else { return }
        confirmDestructive("导入备份", "相同设备将被覆盖, 其它设备保留。确定导入吗？", confirmTitle: "导入") {
            doImport()
        }
    }
    private func doImport() {
        guard let data = importText.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            app.showToast("不是有效的备份包"); return
        }
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        armMigrateWizard(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("导入完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        importText = ""
    }

    // 包3/idea 112: 换机恢复后立起验证向导 — 设备 Tab 逐锁点按验证连接, 全部通过后自动收起
    private func armMigrateWizard(_ r: (imported: Int, overwritten: Int)) {
        guard r.imported + r.overwritten > 0 else { return }
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        DB.store.set("kf_migrate_pending", ISO8601DateFormatter().string(from: Date()))
    }

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
            let envelope = try CryptoBox.encryptText(text, password: cloudPw)
            try await CloudSync.push(acct: cloudAcct, app: cloudApp, envelope: envelope)
            persistCloudConfig()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Milestones.recordBackup()   // 980 备份卫士
            app.evaluateAchievements()
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
            let text = try CryptoBox.decryptEnvelope(envelope, password: cloudPw)
            guard let data = text.data(using: .utf8),
                  let bundle = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
                throw DFUError.msg("云端数据不是有效备份包")
            }
            // 不直接落盘: 交给 confirmationDialog, 用户确认后才覆盖本机
            pendingRestore = bundle
        } catch { app.showToast(error.localizedDescription) }
    }


    // ---------- 包8: 备份工作室入口 (导出向导/恢复/WebDAV策略/换机迁移) ----------
    private var studioSection: some View {
        Section("备份工作室") {
            Button {
                showStudio = true
            } label: {
                Label("打开备份工作室", systemImage: "wrench.and.scissors")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
            }
            Text("导出向导 · 恢复预演 · WebDAV 策略 · 换机迁移 · 完整性信任 (包8)。")
                .font(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyPendingRestore() {
        guard let bundle = pendingRestore else { return }
        pendingRestore = nil
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        armMigrateWizard(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        cloudPw = ""   // 口令用完即弃, 不留在内存里等下次
    }
}