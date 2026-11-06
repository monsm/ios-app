// BackupScreen.swift —— 备份与恢复。
//
// 两条硬规则：
//   1. 不生成明文备份文件 —— 口令为空就不给导出。
//   2. 导入先预览、再写盘；校验和不匹配只警告，不硬拒（老版本导出的包仍然要能回来）。
import SwiftUI
import UIKit

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

            if let last = Milestones.lastBackupAt {
                Text("上次备份：\(When.ago(Int64(last.timeIntervalSince1970 * 1000)))")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .padding(.top, 8)
            }

            SectionHead(index: "01", title: "导出")
            FieldInput(placeholder: "设置一个备份口令（至少 8 位）", text: $passphrase, secure: true)
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
            }
            .padding(.top, 12)

            if let exported {
                Text("信封 \(exported.count) 字符 · 已加密")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ok)
                    .padding(.top, 8)
                ShareLink(item: exported) {
                    Text("分享备份文件")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.brass)
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

            if importing {
                TextEditor(text: $importText)
                    .type(T.F.mono)
                    .frame(height: 130)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(T.C.glass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
                    }
                    .padding(.top, 10)

                FieldInput(placeholder: "备份口令", text: $importPassword, secure: true)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    GhostButton(title: "预览", symbol: "eye") {
                        Task { await doPreview() }
                    }
                    GhostButton(title: "恢复", symbol: "arrow.down.to.line") {
                        Task { await doRestore() }
                    }
                }
                .padding(.top, 10)

                if let preview {
                    GlassSurface(radius: 18) {
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

            Text("导入是「只增不减」：本机已有的同名凭证会保留，不会被覆盖。恢复前会自动写一个回滚点。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
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
        errorLine = nil
        preview = nil
        do {
            let result = try BackupStudio.parsePreview(text: importText,
                                                       password: importPassword.isEmpty ? nil : importPassword)
            preview = result.preview
        } catch {
            errorLine = error.localizedDescription
        }
    }

    private func doRestore() async {
        errorLine = nil
        busy = true
        defer { busy = false }
        do {
            let result = try BackupStudio.parsePreview(text: importText,
                                                       password: importPassword.isEmpty ? nil : importPassword)
            let outcome = try BackupStudio.restore(result.bundle)
            preview = result.preview
            message = "已恢复 \(outcome.imported) 条新增 · \(outcome.overwritten) 条覆盖 · \(outcome.skipped) 条跳过"
            await app.reload(refreshStatus: false)
        } catch {
            errorLine = error.localizedDescription
        }
    }
}
