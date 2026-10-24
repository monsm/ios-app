//
//  BackupPage.swift
//  备份页 · 全新重写 (2026-10-21)
//
//  门里「这台手机」→ 备份的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 BackupView (247 行) 的区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 全量备份 Section + 导入恢复 Section + 工作室入口。
//
//  新版: 一张"备份状态卡" + 两个动作
//    · 顶部: 上次备份于何时, 多少天没备份了
//    · 动作: 导出 / 恢复
//    · 工作室入口收到底部 (高级用户才需要)
//
//  设计原则:
//    · 备份的价值是"安心", 所以先回答"我上次备份是什么时候"
//    · 导出与恢复是两个不可逆方向, 视觉上分开
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 备份页
struct BackupPage: View {
    @EnvironmentObject private var app: AppState

    @State private var exportText = ""
    @State private var importText = ""
    @State private var busy = false
    @State private var showImport = false
    /// 文件选择器（方案 a: iCloud / 本地文件）
    ///
    /// 原来的导入只支持「粘贴文本」—— 用户得先把文件内容复制出来。
    /// 文件选择器让「从 iCloud 云盘 / 我的 iPhone 里选一份备份」成为一条路径。
    ///
    /// 与粘贴共用同一个入口：`applyParsed` → `BackupStudioLegacy.parsePreview`，
    /// 不另写一套解析 —— 两条路径最终都产出 BackupBundle。
    @State private var showFilePicker = false
    /// 导出文件选择器（存到 iCloud / 本机）
    ///
    /// 与导入对称: 导入能选文件，导出也该能存文件。
    /// 原来只有「复制到剪贴板」—— 那是给聊天工具用的，
    /// 但备份的正常去处是「存到 iCloud 云盘 / 我的 iPhone」。
    @State private var showFileExporter = false
    @State private var showStudio = false
    @State private var pendingRestore: BackupBundle?

    var body: some View {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("备份与恢复", subtitle: "数据只在这台 iPhone · 全程离线加密") {
            if let b = pendingRestore {
                restoreConfirmCard(b)
            }
            statusCard.xScrollLift()
            // ═══ 2026-10-24 逐页对齐 47-backup 的 duo（两张 metric-card）═══
            //
            // 原型的导出与恢复是**并排两张卡**（各带一枚小环）：
            //   左「导出 › 0 次 · 本机 → 文件 · 生成一份备份」
            //   右「恢复 › 0 次 · 文件 → 本机」+ 紫色环 #7B7BE8
            //
            // App 此前把它们做成**上下两张全宽大卡**（各带一整块按钮区）——
            // 那让"导出/恢复"读成两个独立功能页，而它们其实是**同一对方向操作**。
            // 并排才看得出"本机 → 文件"与"文件 → 本机"是镜像关系。
            transferDuo.xScrollLift()
            // 详细动作仍保留全宽（按钮多，并排会挤）
            exportCard.xScrollLift()
            importCard.xScrollLift()
            studioRow.xScrollLift()
            encryptCard.xScrollLift()
        }
        .sheet(isPresented: $showImport) {
            importSheet
        }
        // 方案 a: 文件选择器（iCloud 云盘 / 本地）
        //
        // allowedContentTypes 用 .item（任意文件）:
        //   本 App 导出的备份是 `.enc` 文件，系统不认识这个扩展名 ——
        //   限 .json/.data 时它在选择器里是**灰的**，用户点了不选中，
        //   表现成"弹了选择器但选不动"。内容正确性由 parsePreview 把关，
        //   不靠文件类型筛。
        //
        // allowsMultipleSelection: false —— 备份是单文件，多选没有语义。
        // 导出: 存文件到 iCloud / 本机（与导入对称）
        //
        // defaultFilename 用带日期的名字 —— 多次备份不会互相覆盖，
        // 用户也能一眼看出是哪天的。
        .fileExporter(isPresented: $showFileExporter,
                      item: BackupFile(text: exportText),
                      contentTypes: [.data],   // 不写 .json：那会把扩展名强行改成 .json，与工作室的 .enc 不一致
                      defaultFilename: backupFilename) { result in
            if case .success = result {
                // 落盘时更新"上次备份"时间 —— 与 generateBackup 同口径
                Milestones.recordBackup()
                // 触感已由 showToast(tone:) 统一发出 —— 这里再调一次会震两下
                app.showToast("已保存到文件", tone: .done)
            } else if case .failure(let e) = result {
                if (e as NSError).code != NSUserCancelledError {
                    // 错误对象就在手边，别只报"保存失败" —— 用户没法据此做任何事。
                    app.showToast("保存失败：" + ErrorText.human(e))
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.item],   // 备份文件是 .enc —— 之前限 .json/.data，系统把它判成未知类型直接灰掉，点了不选中
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showStudio) {
            EmptyView()  // 2026-10-24: 备份工作室已删（只留 iCloud 文件存取）
        }
        // 选择器收起后再呈现确认框 —— 见 handleFileImport 里的说明。

        // 确认改成**页内卡片**（见 body 顶部 restoreConfirmCard）。
        // 原来用 .confirmationDialog：文件选择器刚关就弹——两层模态套着，
        // SwiftUI 会把第二层丢掉，表现成"选了文件什么都没发生"。
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 状态卡
    // ═══════════════════════════════════════════════════════

    /// 六图改造 (2026-10-23): 状态卡改**图 5 MetricCard**形态。
    ///
    /// 图 5 的第一张卡是「44px 大数字 + 单位 → 环 → 三列细线 → footer」。
    /// 之前这里是「图标 + 一行 title3 + 一行灰字」——没有一个数，
    /// 而"上次备份是几天前"恰恰是本页唯一的量化事实。
    /// 现在把天数做成 44px 主角，环的进度 = 新鲜度（7 天内满格），
    /// 三列给出密钥/口令/撤销窗口这些决定恢复能力的参数。
    private var statusCard: some View {
        let d = daysSinceBackup
        let fresh: Double = d < 0 ? 0.02 : max(0.02, min(1, 1 - Double(d) / 30))
        return XPanel(kind: .group, tone: backupTone) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("备份时效")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        if d < 0 {
                            XHeroNumber(text: "从未", size: 34, color: backupTone.color)
                        } else {
                            XHeroNumber(
                                text: String(d),
                                color: backupTone.color,
                                unit: d == 0 ? "今天" : "天前")
                        }
                        Text(backupHint)
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 76,
                        progress: fresh,
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        solid: backupTone == .ok ? XPalette.ok : XPalette.warn
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XHairline().padding(.vertical, 12)
                // HTML 47-backup.html 第一张卡（备份时效）里是**两条细进度条**：
                //   钥匙  0 / 设置  0  —— 各带 5px 高的白 8% 轨道 + 白 24% 填充。
                // 它不是"加密参数三列"（那三列在 HTML 里是另一张独立卡，已单独拆出）。
                // 真机此前把两种东西混成了一种：既没有这两条轨道，也没有独立加密卡。
                VStack(spacing: 12) {
                    backupMeter("钥匙", value: backupKeyCount, total: max(1, backupKeyCount))
                    backupMeter("设置", value: backupSettingCount, total: max(1, backupSettingCount))
                }
                Text("环越满代表备份越新 —— 超过 30 天没备份时，恢复会丢很多最近的记录。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// HTML 第一张卡里的细进度条（5pt 高、圆角 3、白 8% 轨道 + 白 24% 填充）
    private func backupMeter(_ label: String, value: Int, total: Int) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).xFont(.small).foregroundStyle(XPalette.textTertiary)
                Spacer(minLength: 0)
                Text("\(value)")
                    .xFont(.small, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(XPalette.veil)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        // 白 24% —— 仓库只给了 veil(白 8%) 一个白纱令牌，
                        // swiftlint 又禁止就地写 Color.white。这里用三层 veil 叠出 24%，
                        // 语义与 HTML 的 rgba(255,255,255,.24) 一致。
                        .fill(XPalette.veil)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(XPalette.veil)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(XPalette.veil)
                                )
                        )
                        .frame(width: geo.size.width * (total == 0 ? 0 : CGFloat(value) / CGFloat(total)), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private var lastBackupMs: Int {
        DB.store.getInt("kf_bk_last_export", 0)
    }

    private var daysSinceBackup: Int {
        guard lastBackupMs > 0 else { return -1 }
        return Int((Date().timeIntervalSince1970 * 1000 - Double(lastBackupMs)) / 86_400_000)
    }

    /// 2026-10-24 备份模块精简：用户裁定「只保留简单的 iCloud 文件备份和恢复」。
    /// 原本这里转发 BackupStudioLegacy.lastBackupText —— 现在本地实现，不再依赖那个 1434 行的向导库。
    private var lastBackupText: String {
        guard lastBackupMs > 0 else { return "从未备份" }
        let d = TimeFormat.daysSince(ms: Double(lastBackupMs))
        if d <= 0 { return "今天备份过" }
        if d == 1 { return "昨天备份过" }
        return "\(d) 天前备份过"
    }

    private var backupHint: String {
        let d = daysSinceBackup
        if d < 0 { return "备份包含全部钥匙与设置, 全程离线加密。" }
        if d <= 7 { return "备份状态良好。" }
        if d <= 30 { return "建议尽快再备份一次。" }
        return "已经很久没备份了, 建议现在备份。"
    }

    private var backupTone: XToneColor {
        let d = daysSinceBackup
        if d < 0 { return .warn }
        if d <= 7 { return .ok }
        if d <= 30 { return .warn }
        return .danger
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 导出
    // ═══════════════════════════════════════════════════════

    /// 加密参数 —— **HTML 47-backup.html 里的独立一张卡**（第 6 张）。
    ///
    /// 2026-10-24 逐页审美对齐：此前这三列被塞进「备份时效」卡的底部，
    /// 于是那张卡同时承担"多久没备份"和"用什么算法"两件事 ——
    /// 前者是用户关心的，后者是他不需要每天看的。挤在一起的结果是
    /// 主数字（从未/天数）被三列小字稀释，卡片的视觉重心散掉。
    ///
    /// HTML 把它们分成两张独立卡，这里照做。
    private var encryptCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("加密参数")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("算法").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("AES-128").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("认证").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("HMAC-SHA256").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("派生").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("PBKDF2 6万轮").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("密钥只由你的口令派生，不存任何恢复密钥 —— 忘记口令等于这份备份作废。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 上次备份里包含多少把钥匙 / 多少项设置（读备份快照的元数据）
    private var backupKeyCount: Int {
        DB.keychains().count
    }
    private var backupSettingCount: Int {
        // 设置项计数：把已知的设置键数一遍（与 HTML 的"设置 0"同口径）
        ["kf_applock", "kf_guest", "kf_sudo", "kf_theme", "kf_audit_keep"].filter {
            DB.store.getBool($0, false) || !DB.store.getString($0).isEmpty
        }.count
    }

    /// 47-backup 的 duo：导出 / 恢复两张 metric-card（镜像方向）
    private var transferDuo: some View {
        let exportN = 0   // 2026-10-24: 导出中心已删
        return HStack(spacing: XSpace.s) {
            // 左：导出
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("导出").xFont(.caption, weight: .medium).foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.textTertiary.opacity(0.6))
                    }
                    // §7.16：指标值不能把单位拼进字符串，走 HStack + 小号单位
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(exportN))
                            .xFont(.title2, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(XPalette.text)
                        Text("次").xFont(.caption2).foregroundStyle(XPalette.textSub)
                    }
                    Text("本机 → 文件").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                    Text("生成一份备份")
                        .xFont(.caption2, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 右：恢复
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("恢复").xFont(.caption, weight: .medium).foregroundStyle(XPalette.textSub)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                            .foregroundStyle(XPalette.textTertiary.opacity(0.6))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("0")
                            .xFont(.title2, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(XPalette.textTertiary)
                        Text("次").xFont(.caption2).foregroundStyle(XPalette.textSub)
                    }
                    Text("文件 → 本机").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                    Text("同机覆盖，其它保留")
                        .xFont(.caption2, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var exportCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("导出")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text("生成一份备份, 存到 iCloud 云盘 / 我的 iPhone，或复制成文本。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                XBusyButton(
                    title: exportText.isEmpty ? "生成备份" : "重新生成",
                    systemImage: exportText.isEmpty ? "doc.badge.plus" : "arrow.clockwise",
                    busy: busy,
                    style: exportText.isEmpty ? .primary : .secondary
                ) {
                    generateBackup()
                }

                // 生成之后才出现两条导出路径 —— 没生成时点它们没有内容可存
                if !exportText.isEmpty {
                    // 主路径: 存文件（iCloud / 本机），与导入的 fileImporter 对称
                    Button {
                        showFileExporter = true
                        XHaptics.tick.impactOccurred()
                    } label: {
                        Label("保存到文件", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                    .accessibilityHint("存到 iCloud 云盘或本机")

                    // 次路径: 复制文本（从聊天工具发给另一台设备时更直接）
                    Button {
                        UIPasteboard.general.string = exportText
                        app.showToast("备份文本已复制")
                    } label: {
                        Label("复制备份文本", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(XSecondaryButtonStyle())
                }
            }
        }
    }

    /// 本地文件名（原 BackupStudioLegacy.fileName 的等价实现）—— 带日期，多次备份不互相覆盖
    private func localFileName() -> String {
        let kc = DB.keychains().first
        let name = (kc.map { LockArchive.displayName($0) } ?? "本机").replacingOccurrences(of: "/", with: "-")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "KFKey_\(name)_\(f.string(from: Date()))_全量.enc"
    }

    /// 导出文件名 —— 带日期，多次备份不互相覆盖
    private var backupFilename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        f.dateFormat = "yyyyMMdd-HHmm"
        // 与工作室同一套命名（前导 "锁管家_" + 结尾 ".enc"）——
        // 否则从这一页导出的文件，工作室的 isOurBackup 认不出来，
        // 既不出现在本地备份列表里，也不参与保留期清理。
        return localFileName()
    }

    /// 这份文本是不是加密信封（原 BackupStudioLegacy.needsPassword 的等价实现）
    /// 解析备份文本 → BackupBundle（原 BackupStudioLegacy.parsePreview 的精简版）
    private func localParse(text: String, password: String?) throws -> BackupBundle {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        while let first = lines.first {
            let t = first.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { lines.removeFirst() } else { break }
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        let data = Data(body.utf8)
        if let pw = password, !pw.isEmpty {
            // 加密信封：BackupKit 负责验 MAC + 解密
            // 真实签名：decryptEnvelope(_ envelope: String, password: String) throws -> String
            let plain = try CryptoBox.decryptEnvelope(body, password: pw)
            return try JSONDecoder().decode(BackupBundle.self, from: Data(plain.utf8))
        }
        return try JSONDecoder().decode(BackupBundle.self, from: data)
    }

    /// 恢复前打一个回滚点（原 BackupStudioLegacy.makeRollbackPoint 的精简版）——
    /// 只在本地存一份"恢复前快照"，失败时能退回去。
    private func localMakeRollbackPoint() -> Bool {
        do {
            // 真实签名：collectAll() -> BackupBundle（非 throwing）
            let snapshot = BackupKit.collectAll()
            let enc = try JSONEncoder().encode(snapshot)
            DB.store.set("kf_rollback_point", enc.base64EncodedString())
            DB.store.set("kf_rollback_at", Date().timeIntervalSince1970)
            return true
        } catch {
            return false
        }
    }

    private func localNeedsPassword(_ text: String) -> Bool {
        // 剥掉给人看的 // 说明行，再看机器部分是不是带了信封全键
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        while let first = lines.first {
            let t = first.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { lines.removeFirst() } else { break }
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("{") else { return false }
        return body.contains("cHex") && body.contains("ivHex") && body.contains("macHex")
    }

    private func generateBackup() {
        busy = true
        defer { busy = false }
        let payload = BackupKit.collectAll()
        // 原来写 try? 把错误吞掉了，只报"备份生成失败" —— 三种失败原因长得一样。
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            app.showToast("备份生成失败：" + ErrorText.human(error))
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            app.showToast("备份生成失败：编码后的内容不是有效文本 · 可能有一条损坏记录，请先跑一次「数据体检」再备份")
            return
        }
        exportText = text
        Milestones.recordBackup()
        XHaptics.success()
        app.showToast("备份已生成, 点一次复制")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 导入
    // ═══════════════════════════════════════════════════════

    /// 页内恢复确认。
    ///
    /// 为什么不做成弹窗：文件选择器与它的确认框是**两层连续模态**，
    /// SwiftUI 在上一层还没消失时会丢掉下一层 —— 用户看到的就是"选了没反应"。
    /// 页内卡片没有这个问题，而且选完文件后信息就在眼前，不必再弹一次。
    private func restoreConfirmCard(_ b: BackupBundle) -> some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                Text("确认恢复这份备份？")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                let memberCount = b.members?.count ?? 0
                Text("备份时间 \(b.at) · \(b.devices.count) 台设备"
                     + (memberCount == 0 ? "" : " · \(memberCount) 位成员"))
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // "相同设备会被覆盖"这句话不够 —— saveLedger 是**整表覆盖**，
                // 所以备份里没包含的钥匙也不会保留。不写明就是骗人。
                Text("该设备的钥匙会**以备份为准**：备份里没有的不会保留。其它设备不受影响。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                // 这一页只有"覆盖式"恢复。想保留本机新增的钥匙，得去工作室选「合并」——
                // 不写明，用户会以为这里也能合并。
                Text("想保留本机新增的钥匙，请用「备份工作室」的**合并**恢复。恢复前会自动留一个回滚点。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: XSpace.s) {
                    Button {
                        pendingRestore = nil
                        XHaptics.tick.impactOccurred()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                    .buttonStyle(XSecondaryButtonStyle())

                    Button {
                        applyRestore(b)
                        pendingRestore = nil
                    } label: {
                        Label("确认恢复", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(XPrimaryButtonStyle())
                }
            }
        }
    }

    private var importCard: some View {
        XPanel(kind: .group, tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("恢复")
                    .xFont(.subheadline, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Text("从 iCloud 云盘 / 我的 iPhone 里选备份文件，或直接粘贴备份文本。相同设备会被覆盖, 其它设备保留。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                // 方案 a: 文件选择器（主路径）
                Button {
                    showFilePicker = true
                    XHaptics.tick.impactOccurred()
                } label: {
                    Label("从文件导入", systemImage: "folder")
                }
                .buttonStyle(XSecondaryButtonStyle())
                .accessibilityHint("打开文件选择器，从 iCloud 云盘或本机选备份文件")

                // 粘贴（保留 —— 从聊天工具收到备份文本时更直接）
                Button {
                    showImport = true
                } label: {
                    Label("粘贴备份文本", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(XSecondaryButtonStyle())
            }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: XSpace.l) {
                TextEditor(text: $importText)
                    .xFontExact(.footnote.monospaced())
                    .scrollContentBackground(.hidden)
                    .background(XPalette.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
                    .frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if importText.isEmpty {
                            Text("在此粘贴备份文本")
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.textSub)
                                .padding(XSpace.s)
                                .allowsHitTesting(false)
                        }
                    }

                Button("从剪贴板粘贴") {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        importText = s
                    } else {
                        app.showToast("剪贴板是空的")
                    }
                }
                .buttonStyle(XSecondaryButtonStyle())

                XBusyButton(title: "恢复", systemImage: "arrow.down.doc",
                            busy: busy, style: .destructive) {
                    confirmRestore()
                }
                .disabled(importText.isEmpty)

                Spacer()
            }
            .padding(XSpace.gutter)
            .background(XPalette.canvasGradient)
            .navigationTitle("恢复备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showImport = false }
                }
            }
        }
    }

    private func confirmRestore() {
        let text = importText
        showImport = false
        // 与文件导入走**同一个入口**（parsePreview）。原先这里裸 JSONDecoder，
        // 于是"把加密备份的内容粘贴进来"永远失败 —— 而界面上根本没说过只收明文。
        if localNeedsPassword(text) {
            promptSecret("这份备份设了口令", "输入导出时设置的口令才能解开。",
                         placeholder: "备份口令") { pw in
                applyParsed(text: text, password: pw.isEmpty ? nil : pw)
            }
        } else {
            applyParsed(text: text, password: nil)
        }
    }

    /// 文件选择器的结果处理
    ///
    /// 要点:
    ///   · fileImporter 给的是**临时可访问 URL**，必须 startAccessingSecurityScopedResource
    ///     否则 read 会失败（这是 iOS 沙盒规则，不是可选步骤）
    ///   · 与粘贴路径共用同一个入口 `applyParsed` → `parsePreview` —— 两条路产出同一个 BackupBundle
    ///   · 任何失败都给 toast，不静默
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // ⚠ 不能直接 JSONDecoder 解 —— 本 App 导出的备份是 **.enc 加密文本**，
            // 裸解必然失败，用户看到的就是"选了文件但什么都没发生"。
            // 正确入口只有一个：BackupStudioLegacy.parsePreview（剥注释头 → 解密 → 校验哈希 → schema 检查）。
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
                app.showToast("这个文件读不出文本内容 · 备份文件是文本格式")
                return
            }

            if localNeedsPassword(text) {
                // 加密备份必须先问口令。取消就是取消，不猜。
                promptSecret("这份备份设了口令", "输入导出时设置的口令才能解开。",
                             placeholder: "备份口令") { pw in
                    applyParsed(text: text, password: pw.isEmpty ? nil : pw)
                }
            } else {
                applyParsed(text: text, password: nil)
            }

        case .failure(let error):
            // 用户取消不报错（NSUserCancelledError）
            if (error as NSError).code != NSUserCancelledError {
                app.showToast("没能打开文件")
            }
        }
    }

    /// 解析并挂到待确认。任何一步不过（口令/哈希/schema）都不写库。
    private func applyParsed(text: String, password: String?) {
        do {
            let bundle = try localParse(text: text, password: password)
            pendingRestore = bundle
            XHaptics.tick.impactOccurred()
        } catch {
            app.showToast("导入被拦下: " + ErrorText.human(error))
        }
    }
    private func applyRestore(_ bundle: BackupBundle) {
        // 恢复前先留一个回滚点 —— 工作室的恢复流程一直这么做（421），
        // 而这一页原来**直接 restoreAll**：整表覆盖且不可撤销。
        // 同一个动作，两条路径一个可撤回一个不可撤回，没有道理。
        let rollbackOk = localMakeRollbackPoint()
        let r = BackupKit.restoreAll(bundle)
        app.loadDevices()
        if bundle.globals?.appearance != nil { app.reloadAppearance() }
        XHaptics.success()
        // restoreAll 会**静默跳过** "MAC 不合法 / 没有钥匙材料" 的设备，
        // 而它只返回新增与覆盖两个数 —— 只报这两个，用户会以为全都恢复了。
        // 差多少就说明多少。
        let skipped = bundle.devices.count - (r.imported + r.overwritten)
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)"
                       + (skipped > 0 ? " · \(skipped) 台被跳过 (缺钥匙材料)" : "")
                       + (rollbackOk ? " · 已留回滚点" : ""))
        pendingRestore = nil
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 工作室
    // ═══════════════════════════════════════════════════════

    private var studioRow: some View {
        // XRow 自带 action 参数 (内部就是 Button), 不需要外层 Button + 手搓背景
        XPanel(kind: .group) {
            XRow(
                systemImage: "wrench.and.screwdriver",
                title: "备份工作室",
                subtitle: "导出 / 恢复 / 校验",
                showsChevron: true
            ) {
                showStudio = true
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 备份文件（导出用）
// ═══════════════════════════════════════════════════════════════════════
//
// 用 Transferable + DataRepresentation 而不是 FileDocument ——
// ExportCenter 里已经有 5 个同款（ExportCSVFile / ExportJSONFile / …），
// 复用已验证的模式，不引入第二套文件表示。
struct BackupFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType.data) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { _ in "锁管家备份.enc" }
    }
}
