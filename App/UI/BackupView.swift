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
    /// 云盘账号与应用密码**只有本机存储这一份真相**：这里刻意不拍 `@State` 快照。
    /// 原先是 `@State … = DB.store.getString(...)` + `.onDisappear { persistCloudConfig() }`，
    /// 而本页与工坊 (`WebDAVStudioView`，经 NavigationLink/sheet 打开) 写的是同一对键 ——
    /// 在工坊里改完账号回到本页再关掉，`onDisappear` 就把**进页时那份旧快照**写回去，
    /// 刚改的凭据被静默覆盖 (第一百六十六批 §10.38)。读写穿透后没有"旧快照"这个东西。
    /// 加密口令**不入库**，所以它仍是 `@State`（每次输入、用完即弃）。
    /// 输入框直写本机存储：与工坊那页共用一份真相，谁改完另一页立刻读到新值。
    @State private var pendingRestore: BackupBundle?
    /// 云端已下载但尚未经用户确认的备份包 (nil = 无待确认的恢复)

    // 2026-10-15 走查·CI 补刀: 上一批改这一行时把 `showStudio` **改名成了** `showWebDAV`，
    // 而 `$showStudio`(:64) 与 `showStudio = true`(:303) 两处用法都还在 ⇒ 编译报 cannot find 'showStudio'（run 99）。
    // 两个 sheet 各自一枚状态，顺带把这批遗留的 8 空格缩进收齐。
    @State private var showStudio = false      // 备份工作室（自带 NavigationStack ⇒ 只能 sheet，不能 push）

    /// 内容是否已经嵌在外部导航容器里。2026-10-15 走查 §7.4-16: 这一页**自带 NavigationStack**,
    /// 有两个呈现点 —— 设置页的 sheet (要自己那层栏) 和设备页快捷格的 `quickDestination` push
    /// (那层栏已经在外面了)。push 那侧不传 true 就叠出两层导航栏。形状照 `AddPwdView` 的 embedded 抄,
    /// 那是本仓作者已有的解法。判据原文见本文件上方那条"自带 NavigationStack 的页只能走 sheet"。
    var embedded: Bool = false

    private var listContent: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
                    exportSection.xScrollLift()
                    importSection.xScrollLift()
                    studioSection.xScrollLift()
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    var body: some View { vkBody }
    var vkBody: some View {
        // AnyView 擦平两分支类型差异 (与 AddPwdView 同一写法): 两支只差最外层那一只容器
        (embedded ? AnyView(listContent) : AnyView(NavigationStack { listContent }))
        .confirmationDialog("从云端恢复", isPresented: pendingRestoreBinding, titleVisibility: .visible) {
            Button("覆盖本机 \(DB.keychains().count) 台设备", role: .destructive) { applyPendingRestore() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("云端备份里包含 \(pendingRestore?.devices.count ?? 0) 台门锁。恢复后同名设备会被云端数据覆盖，本机现有改动将丢失。")
        }
        .sheet(isPresented: $showStudio) { BackupStudioView() }
    }

    // pendingRestore != nil 即为"待确认", 确认/取消后都要清空以防重复触发
    private var pendingRestoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } })
    }

    // ---------- 全量备份 ----------
    private var exportSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("全量备份")
                Text("导出全部门锁、钥匙、密码台账与家人档案为一整段文本 (含敏感密钥, 请妥善保管)。")
                    .xFont(.caption).foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                XBusyButton(title: "生成备份文本", systemImage: "doc.text", busy: false) {
                    Milestones.recordBackup()   // 980 备份卫士
                    exportText = BackupCanonical.exportText(BackupKit.collectAll())
                    BackupStudio.markExportSize(exportText)   // 193: 记本次尺寸, 下次预估行对比用
                    app.evaluateAchievements()
                }
                // 822 从未备份的信封: 没有备份时这页最该说的不是"怎么导出"，而是"现在一个都没有"。
                // 文案不写"建议每周一次"这种本 App 没有依据的规范；给的是**已发生的事实**与下一步动作。
                if Milestones.lastBackupAt == nil {
                    HStack(alignment: .top, spacing: XSpace.s) {
                        Image(systemName: "envelope")
                            .font(.system(size: XIcon.md))
                            .foregroundStyle(XPalette.accentText)
                        VStack(alignment: .leading, spacing: XSpace.xxs) {
                            Text("还没有备份").xFont(.subheadline, weight: .medium)   // 822 还没有备份
                            Text("本机从未生成过备份文本，也没有上传成功记录。手机丢失或重装即不可恢复。")
                                .xFont(.caption).foregroundStyle(XPalette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else if let at = Milestones.lastBackupAt {
                    VStack(alignment: .leading, spacing: XSpace.xxs) {
                        Text("上次备份 " + at.formatted(date: .abbreviated, time: .shortened))   // 822 上次备份
                            .xFont(.caption).foregroundStyle(XPalette.textSub)
                        // 822 建议备份时间: 读「备份工作室」的节奏档 (198 的 kf_bk_cadence, 本处为它的读方),
                        // 到期与否按上次备份时刻实算; 节奏为「仅手动」时不建议 —— 没有节奏就没有"到期"这一说。
                        if let tip = Self.backupDueTip(cadence: BackupStudio.cadence, last: at) {
                            Text(tip).xFont(.caption).foregroundStyle(XPalette.textSub)
                        }
                        // 193 体积预估: 本次预计 vs 上次实际 (备份工作室同样一行, 这里补全量导出入口的对照)
                        if let est = BackupStudio.estimateBytes() {
                            Text(BackupStudio.sizeText(est)).xFont(.caption).foregroundStyle(XPalette.textSub)
                        }
                    }
                }
                if !exportText.isEmpty {
                    VStack(alignment: .leading, spacing: XSpace.s) {
                        Text("共 \(exportText.count) 字符")
                            .xFont(.caption).foregroundStyle(XPalette.textSub)
                        Text(exportText)
                            .xFont(.caption.monospaced())
                            .lineLimit(8).truncationMode(.tail)
                            .textSelection(.enabled) // 也可手动复制
                        ShareLink(item: exportText, preview: SharePreview("离线锁管家备份"))
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    // ---------- 导入恢复 ----------
    private var importSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("导入恢复")
                Text("粘贴备份文本后导入。相同设备将覆盖, 其它设备保留 (门锁无需重置)。")
                    .xFont(.caption).foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("粘贴备份文本", text: $importText, axis: .vertical)
                    .xFont(.caption.monospaced())
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        importText = s
                    } else {
                        app.showToast("剪贴板是空的")
                    }
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                        .frame(minHeight: XHit.min)
                }
                .disabled(importText.isEmpty)
                Button("导入", role: .destructive) { confirmImport() } // 覆盖同名设备, 属破坏性动作
                    .disabled(importText.isEmpty)
            }
        }
    }


    private enum CloudMode { case push, pull }

    // ---------- 本地导入 ----------
    private func confirmImport() {
        guard !importText.isEmpty else { app.showToast("请先粘贴备份文本"); return }
        // 原来这里有一句 guard !busy —— 但 busy 从来没有被置位过，
        // 因为导出与导入都是**全同步**实现（collectAll / parsePreview + restoreAll）。
        // 它暗示了一个并不存在的异步窗口，留着只会让后来者以为这里有并发保护。
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




    // ---------- 包8: 备份工作室入口 (导出向导/恢复) ----------
    private var studioSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("备份工作室")
                Button {
                    showStudio = true
                } label: {
                    Label("打开备份工作室", systemImage: "wrench.and.scissors")
                        .xFont(.subheadline, weight: .semibold)
                        .foregroundStyle(XPalette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: XHit.min)
                }
                Text("导出向导 · 恢复预演 · 完整性信任。")
                    .xFont(.caption).foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applyPendingRestore() {
        guard let bundle = pendingRestore else { return }
        pendingRestore = nil
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        if bundle.globals?.appearance != nil { app.reloadAppearance() }   // 894 带外观段才刷, 免得白重建一次全树
        armMigrateWizard(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 822: 按节奏档 (weekly/monthly) 与上次备份时刻算建议; 仅手动档给 nil (没有节奏就没有到期)。
    private static func backupDueTip(cadence: String, last: Date) -> String? {
        let days: Int
        let label: String
        switch cadence {
        case "monthly":
            days = 30
            label = "每月"
        case "weekly":
            days = 7
            label = "每周"
        default:
            return nil
        }
        let due = last.addingTimeInterval(TimeInterval(days) * 86_400)
        if due <= Date() { return "按当前的\(label)节奏, 已经到该再备份一次的时候了" }   // 822 按当前的
        return "按当前的\(label)节奏, 建议 " + due.formatted(date: .abbreviated, time: .shortened) + " 前再备一次"   // 822 前再备一次
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}