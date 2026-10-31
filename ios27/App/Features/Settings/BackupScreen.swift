// BackupScreen.swift —— 备份与恢复。这一屏的主动作是「生成备份」。
//
// 这屏干什么：导出一整段本机数据（门锁 / 凭证 / 成员 / 外观档），或从一段备份文本恢复。
// 备份文件含明文门锁密钥 —— 拿到它的人不需要你的手机就能开你家门，所以危险说明写在最上面。
// 数据从哪来：SettingsStore.shared（上次备份时刻 / 加密开关）+ AppModel（本机数据计数）。
// 主动作：唯一 signal 填充是「生成备份」。恢复是破坏性动作，走描边 + 二次确认。
import SwiftUI
import UIKit

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
    @State private var showRestoreConfirm = false
    @State private var restoreDone: (added: Int, merged: Int)?
    /// 恢复被拦下的原因。不写「失败了」三个字，写清是哪一道闸拦的。
    @State private var restoreError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                SettingsHeader(title: "备份与恢复", tone: tone, status: status)
                studioEntry
                exportPanel
                importPanel
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("恢复这份备份？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复（合并，只增不删）") { runImport() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("导入是合并：本机已有的凭证会保留，同名冲突取本机。若备份里带本机密码摘要，本机密码会被替换成它（可能回滚到旧值）。")
        }
    }

    // MARK: 备份工作室入口（WebDAV / 多份保留 / 换机迁移 / 自检）
    private var studioEntry: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "备份工作室")
                SettingsNote(text: "本机多份备份文件、WebDAV 同步、换机迁移包与数据自检都在工作室里。")
                SecondaryAction(title: "打开备份工作室", systemImage: "square.stack.3d.up") {
                    router.request(.dest(.backupStudio))
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
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
        VStack(spacing: T.S.s) {
            SectionLabel(text: "全量备份", trailing: store.encryptBackup ? "加密" : "明文")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    // 危险说明放最上面：这一屏最重要的信息不是"怎么点按钮"
                    HStack(alignment: .top, spacing: T.S.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(T.F.icon(T.Icon.s))
                            .foregroundStyle(State.critical)
                            .accessibilityHidden(true)
                        Text(store.encryptBackup
                             ? "加密备份也要当密钥文件对待：口令一旦泄露，文件就是明文门锁密钥（skey / pin / 密码）。别发聊天软件，别放共享文件夹。"
                             : "明文备份含门锁密钥（skey / pin / 密码）。任何人拿到它就能开你家门，不需要你的手机 —— 别发聊天软件，别放共享文件夹。")
                            .font(T.F.caption)
                            .foregroundStyle(State.critical)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingRule()

                    ReadingGrid(items: [
                        .init(label: "门锁", value: "\(app.lock == nil ? 0 : 1)", unit: "把"),
                        .init(label: "凭证", value: "\(app.keys.count)", unit: "枚"),
                        .init(label: "成员", value: "\(app.members.count)", unit: "位"),
                        .init(label: "记录缓存", value: "\(app.entries.count)", unit: "条"),
                    ], columns: 2)
                    .padding(.top, T.S.xs)

                    SettingRule()

                    SettingToggle(
                        label: "加密备份",
                        note: "开启后需要设一个密码才能生成。忘记密码 = 这份备份永久作废，所以默认关闭。",
                        isOn: settingsBinding(\.encryptBackup)
                    )

                    if store.encryptBackup {
                        Inset {
                            SecureField("备份密码（至少 8 位）", text: $exportPassword)
                                .font(T.F.body)
                                .textContentType(.newPassword)
                                .accessibilityLabel("备份密码")
                        }
                        if !exportPassword.isEmpty, exportPassword.count < 8 {
                            StatusLine(tone: .attention, text: "至少 8 位 —— 否则加密形同虚设")
                        }
                    }

                    PrimaryAction(title: "生成备份", systemImage: "doc.text", busy: exporting) {
                        generate()
                    }
                    .disabled(store.encryptBackup && exportPassword.count < 8)

                    if !exportText.isEmpty {
                        SettingRule()
                        VStack(alignment: .leading, spacing: T.S.xs) {
                            Text("已生成")
                                .font(T.F.unit)
                                .foregroundStyle(Ink.inkFaint)
                                .tracking(0.6)
                            HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                                Spacer(minLength: 0)
                                Reading(value: "\(exportText.count)", unit: "字符", size: 17)
                            }
                            Text(exportText)
                                .font(T.F.caption.monospaced())
                                .foregroundStyle(Ink.inkSub)
                                .lineLimit(4)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                            SecondaryAction(title: "复制备份文本", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = exportText
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 恢复
    private var importPanel: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "恢复")
            Panel {
                VStack(alignment: .leading, spacing: T.S.m) {
                    if importing {
                        BusyRow(text: "正在解密并校验备份 · 不要离开")
                        SettingRule()
                    }
                    if let restoreError {
                        StatusLine(tone: .critical, text: restoreError)
                        SettingRule()
                    }
                    if let r = restoreDone {
                        StatusLine(tone: .ok, text: "已恢复：新增 \(r.added) 项，合并 \(r.merged) 项")
                        SettingRule()
                    }
                    SettingsNote(text: "粘贴备份文本。导入是合并（只增不删）—— 本机已有的凭证会保留，同名冲突取本机。门锁本身无需重置。")
                    Inset {
                        TextField("粘贴备份文本", text: $importText, axis: .vertical)
                            .font(T.F.caption.monospaced())
                            .lineLimit(3 ... 6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("备份文本")
                    }
                    Inset {
                        SecureField("备份密码（导出时设过密码的才需要填）", text: $importPassword)
                            .font(T.F.body)
                            .accessibilityLabel("备份密码")
                    }
                    SecondaryAction(title: "从剪贴板粘贴", systemImage: "doc.on.clipboard") {
                        if let s = UIPasteboard.general.string, !s.isEmpty {
                            importText = s
                        }
                    }
                    SecondaryAction(title: "恢复这份备份", systemImage: "arrow.down.doc") {
                        showRestoreConfirm = true
                    }
                    .disabled(importText.isEmpty)
                    .opacity(importText.isEmpty ? 0.4 : 1)

                    if importText.isEmpty {
                        SettingsNote(text: "还没有备份文本。下一步：在上面点「生成备份」，再回来把文本粘到这里 —— 或者在换机时把上一条手机上的备份文本复制过来。")
                    }
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: - 动作

    private func generate() {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            // 真链路：collectAll（全部 kf_* 表）→ canonical（与小程序互通）→ 可选加密信封。
            let bundle = BackupKit.collectAll()
            let plain = BackupCanonical.exportText(bundle)
            exportText = store.encryptBackup
                ? try CryptoBox.encryptText(plain, password: exportPassword)
                : plain
            // 980：只有真正生成成功才记一次备份（失败不记）。
            Milestones.recordBackup()
        } catch {
            restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runImport() {
        guard !importText.isEmpty, !importing else { return }
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
                let r = BackupStudio.restore(parsed.bundle)
                restoreDone = (added: r.imported, merged: r.overwritten)
                importText = ""
                await app.reload(refreshStatus: false)
            } catch {
                restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                restoreDone = nil
            }
        }
    }
}
