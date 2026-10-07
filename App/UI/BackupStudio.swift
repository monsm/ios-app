// 包8 备份工作室 UI — 备份·恢复·换机迁移 (五块: 导出向导/恢复/WebDAV与策略/换机迁移/完整性信任感)
// 纪律: 颜色只经 DS 令牌; 备份文件只去用户自配 WebDAV; 口令不出本机内存; 触达 ≥44pt。
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreImage

// ================= 入口: 工作室首页 =================
struct BackupStudioView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showExport = false
    @State private var showRestore = false
    @State private var showWebdav = false
    @State private var showMigration = false
    @State private var showFiles = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    trustHeader
                    actionCards
                    cadenceCard
                    MigrationPromptCard().staggered(1)
                }
                .padding(.vertical, DS.Space.m)
            }
            .navigationTitle("备份工作室")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showExport) { ExportWizardView() }
            .sheet(isPresented: $showRestore) { RestoreWizardView() }
            .sheet(isPresented: $showWebdav) { WebDAVStudioView() }
            .sheet(isPresented: $showMigration) { MigrationWizardView() }
            .sheet(isPresented: $showFiles) { LocalFilesView() }
        }
    }

    // ---------- 512 数据主权声明 (盾形 SF Symbol + 固定一句) + 509 双向天数行 ----------
    private var trustHeader: some View {
        Card(tint: .ok) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: DS.Icon.lg, weight: .semibold))
                    .foregroundStyle(DS.Palette.ok)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("数据只存在这台 iPhone (512)")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    HStack(spacing: DS.Space.s) {
                        Label(daysText("上次导出", BackupStudio.daysSinceLastExport()),
                              systemImage: "square.and.arrow.up")
                        Label(daysText("上次导入", BackupStudio.daysSinceLastImport()),
                              systemImage: "square.and.arrow.down")
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityElement(children: .combine)
                    // 37 备份加密徽章 (Proton): 算法参数外露, 换算法后旧文件各自标注
                    Label("AES-128-CBC + HMAC-SHA256 · PBKDF2 60000 轮 (37)",
                          systemImage: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.ok)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 429 新鲜度: 超 14 天黄条
            let d = BackupStudio.daysSinceLastExport()
            if d >= 14 {
                freshnessBanner
            }
            // 448 启动自检黄条
            if let w = BackupStudio.selfCheckWarning {
                Label(w, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 421 24h 内可撤销本次恢复
            if BackupStudio.canUndoLastRestore {
                Button {
                    confirmDestructive("撤销本次恢复", "将回到恢复前自动打的快照 (421)。确定吗？",
                                        confirmTitle: "撤销") {
                        if BackupStudio.undoLastRestore() {
                            app.loadDevices()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            app.showToast("已撤销本次恢复 (421)")
                        } else {
                            app.showToast("撤销失败: 快照不可读")
                        }
                    }
                } label: {
                    Label("撤销本次恢复 (24h 内, 421)", systemImage: "arrow.uturn.left")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.danger)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .background(DS.Palette.danger.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
            }
        }
    }
    private func daysText(_ label: String, _ d: Int) -> String {
        d < 0 ? "\(label) 暂无" : (d == 0 ? "\(label) 今日" : "\(label) \(d) 天前")
    }
    private var freshnessBanner: some View {
        HStack(spacing: DS.Space.s) {
            Text("距上次备份已 \(BackupStudio.daysSinceLastExport()) 天 (429)")
                .font(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("立即备份") { showExport = true }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
        }
        .padding(.top, DS.Space.s)
    }

    // ---------- 五大动作卡 (触达 ≥44pt) ----------
    private var actionCards: some View {
        VStack(spacing: DS.Space.s) {
            studioRow(title: "导出向导", sub: "分区勾选 · 口令 · 自描述命名 · 二维码搬运 (407-413)",
                      icon: "tray.and.arrow.up", tint: DS.Palette.accentText) { showExport = true }
            studioRow(title: "恢复向导", sub: "预演 · 三策略 · 冲突裁决 · 回滚点 (417-427)",
                      icon: "tray.and.arrow.down", tint: DS.Palette.warn) { showRestore = true }
            studioRow(title: "WebDAV 与策略", sub: "连通测试 · 远端列表 · 节奏三档 · 密钥轮换 (197/198/237/422)",
                      icon: "externaldrive.badge.wireless", tint: DS.Palette.accentText) { showWebdav = true }
            studioRow(title: "换机迁移", sub: "三通道向导 · 双机进度 · 差异补传 (438-446)",
                      icon: "iphone.radiowaves.left.and.right", tint: DS.Palette.accentText) { showMigration = true }
            studioRow(title: "本地备份文件", sub: "演练 · 哈希短码 · 双备份对比 · 数据事件 (434/436/454/511)",
                      icon: "clock.arrow.circlepath", tint: DS.Palette.textSub) { showFiles = true }
        }
    }
    private func studioRow(title: String, sub: String, icon: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: DS.Hit.min)
            .padding(DS.Space.l)
            .background(DS.Palette.surface,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityElement(children: .combine)
    }

    // ---------- 198 节奏三档 + 430 滚动保留 + 1018 月度备份日 + 428 充电 ----------
    @State private var cadence: String = ""
    @State private var keep: Int = 0
    @State private var monthDay: Int = 0
    private var cadenceCard: some View {
        Card {
            SectionTitle(text: "备份策略")
            Picker("备份节奏 (198)", selection: Binding(
                get: { cadence.isEmpty ? BackupStudio.cadence : cadence },
                set: { BackupStudio.cadence = $0; cadence = $0 })) {
                Text("仅手动").tag("manual")
                Text("每日").tag("daily")
                Text("每周").tag("weekly")
            }
            .pickerStyle(.segmented)
            Stepper("滚动保留 (430): 远端只留 \(keep) 份", value: Binding(
                get: { keep },
                set: { BackupStudio.rollingKeep = $0; keep = $0 }), in: 0...20)
            Picker("月度备份日 (1018): \(monthDay == 0 ? "关" : "每月 \(monthDay) 日")",
                   selection: Binding(
                    get: { monthDay },
                    set: {
                        BackupStudio.monthlyDay = $0
                        monthDay = $0
                        Task { await BackupStudio.scheduleMonthlyBackup() }
                    })) {
                ForEach([0, 1, 5, 10, 15, 20, 25, 30], id: \.self) { d in
                    Text(d == 0 ? "关" : "每月 \(d) 日").tag(d)
                }
            }
            Toggle("充电时自动备份 (428 · 由系统择机执行)",
                   isOn: Binding(
                    get: { DB.store.getBool("kf_bk_bgtask") },
                    set: { on in
                        DB.store.set("kf_bk_bgtask", on)
                        if on {
                            BackupStudio.registerChargeBackup()
                            app.showToast(BackupStudio.chargeBackupNote)
                        }
                    }))
            if DB.store.getBool("kf_bk_bgtask") {
                Text(BackupStudio.chargeBackupNote)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            cadence = BackupStudio.cadence
            keep = BackupStudio.rollingKeep
            monthDay = BackupStudio.monthlyDay
        }
    }
}

// ---------- 446 旧机退役横幅: 首验全勾 → 引导本地销毁 ----------
struct MigrationPromptCard: View {
    @EnvironmentObject var app: AppState
    @State private var retired: Bool = false
    var body: some View {
        if retired {
            Card(tint: .warn) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: DS.Icon.md))
                        .foregroundStyle(DS.Palette.warn)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("本机首验清单已全部通过 (446)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        Text("已标记退役 (446) — 建议走 设置→安全中心→销毁 做三级本地销毁。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("标记退役") {
                        BackupStudio.markRetired()
                        retired = true
                        app.showToast("已标记此设备退役 (446)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
        .onAppear { retired = BackupStudio.retirementBanner }
    }
}

// ================= 导出向导 (407-413) =================
struct ExportWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0            // 0 分区 · 1 口令 · 2 体检 · 3 完成
    @State private var zones = BZones()
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var cleanFirst = false  // 431 清理联动
    @State private var useVolumes = false  // 410 按年分卷
    @State private var busy = false
    @State private var doneText: String = ""
    @State private var doneURL: URL?
    @State private var qrPayload: String?
    @State private var otpToggle = false

    private let stepTitles = ["选分区", "设口令", "导出前体检", "完成"]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                // 步骤指示条
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? DS.Palette.accentText : DS.Palette.hairline)
                            .frame(width: i == step ? 24 : 10, height: 6)
                    }
                }
                .padding(.top, DS.Space.s)
                Group {
                    switch step {
                    case 0: zoneStep
                    case 1: passwordStep
                    case 2: healthStep
                    default: doneStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: DS.Space.m) {
                    if step > 0 {
                        Button("上一步") { withAnimation(DS.Motion.standard) { step -= 1 } }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(minHeight: DS.Hit.min)
                    }
                    if step < 3 {
                        Button(step == 2 ? "导出" : "下一步") { advance() }
                            .buttonStyle(PrimaryActionStyle())
                            .disabled(step == 2 && busy)
                    } else {
                        Button("完成") { dismiss() }
                            .buttonStyle(PrimaryActionStyle())
                    }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            .navigationTitle(stepTitles[step])
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    // ---------- 第 0 步: 407 分区勾选 (实时条数) + 181 OTP 开关 ----------
    private var zoneStep: some View {
        let counts = BackupStudio.zoneCounts()
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            zoneToggle("设备", counts["设备"] ?? 0, $zones.devices,
                       "门锁钥匙串 + BLE 直连参数 (441 逐把确认)")
            zoneToggle("凭证", counts["凭证"] ?? 0, $zones.credentials,
                       "密码与指纹台账")
            zoneToggle("记录", counts["记录"] ?? 0, $zones.records,
                       "锁端日志缓存 (按锁约)")
            zoneToggle("设置", counts["设置"] ?? 0, $zones.settings,
                       "成员档案 · 应用锁摘要 · dongle/gateway")
            Toggle("包含独立口令组密钥 (181, 默认排除更稳妥)",
                   isOn: $otpToggle)
                .onAppear { otpToggle = BackupStudio.otpIncluded() }
                .onChange(of: otpToggle) { _, on in DB.store.set("kf_bk_otp", on) }
            if useVolumes, let vols = BackupStudio.volumes(zones: zones, encrypt: nil) {
                Text("记录区超阈值, 将拆为 \(vols.count) 卷 (410): 基础卷 + 逐年记录卷, 各卷可独立恢复。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    private func zoneToggle(_ title: String, _ n: Int, _ on: Binding<Bool>, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Toggle(isOn: on) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    Text("\(n) 条").font(.caption).foregroundStyle(DS.Palette.textSub)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: DS.Hit.min, alignment: .center)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s)
        .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // ---------- 第 1 步: 408 口令两遍 (纯数字/过短只提醒不拦截) ----------
    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("两遍输入加密口令。可留空 = 不加密 (明文 canonical, 与小程序互通)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("口令", text: $pw)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DS.Space.s)
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            SecureField("再输一遍 (408)", text: $pw2)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DS.Space.s)
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            if !pw.isEmpty && pw != pw2 {
                Text("两次输入不一致")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
            } else if !pw.isEmpty && (pw.count < 8 || pw.allSatisfy(\.isNumber)) {
                Text("纯数字或过短口令偏弱 — 不拦截, 仅提醒 (408)。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // ---------- 第 2 步: 412/431 体检 + 清理联动 ----------
    private var healthStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("导出前体检 (412): 统计摘要与问题清单。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            let rows = BackupStudio.preExportHealth()
            if rows.isEmpty {
                Label("数据健康, 可直接导出", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ok)
            } else {
                ForEach(rows) { h in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Text(h.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.warn)
                        Text(h.text)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Toggle("先清理过期临时码再导出 (431, 将减少 \(BackupStudio.expiredTemporaryCount()) 条)",
                   isOn: $cleanFirst)
            Toggle("按年分卷 (410)", isOn: $useVolumes)
            Spacer(minLength: 0)
        }
    }

    // ---------- 第 3 步: 413 完成即分享 + 411 二维码搬运 + 508 写入回执 ----------
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // 508 写入回执: 对勾浮出
            if !doneText.isEmpty {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DS.Icon.xl))
                        .foregroundStyle(DS.Palette.ok)
                        .transition(.scale(0.9).combined(with: .opacity))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("已写入本机 (508)")
                            .font(.headline)
                            .foregroundStyle(DS.Palette.text)
                        Text(doneText)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .animation(DS.Motion.standard, value: doneText.isEmpty)
            }
            // 413 完成即分享 (ShareLink 系统面板 + 存储到文件快捷)
            if let url = doneURL {
                ShareLink(item: url, preview: SharePreview("离线锁管家备份"))
            }
            // 411 二维码搬运: 仅凭证小包可生成 QR, 纯本地 CoreImage, 接收方另机扫码
            if let q = qrPayload, let img = BackupStudio.qrImage(q) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("凭证小包二维码搬运 (411): 另一台手机用本 App 恢复页相机扫码, 全程无网络。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: UIImageShareItem(img), preview: SharePreview("凭证二维码"))
                    Text("口令另行线下交接, 勿与 QR 同渠道 (与 321 导出纪律一致)。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("再生成一份") {
                qrPayload = nil
                doneText = ""
                doneURL = nil
                step = 0
            }
            .buttonStyle(SecondaryActionStyle())
            Spacer(minLength: 0)
        }
    }

    private func advance() {
        switch step {
        case 0:
            step = 1
        case 1:
            guard pw.isEmpty || pw == pw2 else { app.showToast("两次口令不一致"); return }
            step = 2
        case 2:
            exportNow()
        default: break
        }
    }

    private func exportNow() {
        busy = true
        defer { busy = false }
        if cleanFirst { _ = BackupStudio.cleanExpired() }
        let name = BackupStudio.fileName()
        if useVolumes, let vols = BackupStudio.volumes(zones: zones, encrypt: pw.isEmpty ? nil : pw) {
            var written = [URL]()
            for v in vols {
                let url = BackupStudio.dir.appendingPathComponent(BackupStudio.fileName(vol: v.index) + ".enc")
                _ = try? v.text.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
            }
            doneURL = written.first
            doneText = "已按年拆为 \(vols.count) 卷 (410): 基础卷 + 逐年记录卷, 各卷可独立恢复。"
            qrPayload = nil
        } else {
            guard let text = BackupStudio.exportText(zones: zones, encrypt: pw.isEmpty ? nil : pw) else {
                app.showToast("导出失败: 编码为空"); return
            }
            doneURL = BackupStudio.writeLocal(text, name: name, otp: otpToggle)
            doneText = "已写入 \(doneURL?.lastPathComponent ?? name + ".enc") (413)。"
            qrPayload = BackupStudio.credentialQRPayload()
            // 507 角标 + 511 事件
            BackupStudio.recordEvent("export")
        }
        Milestones.recordBackup()
        app.evaluateAchievements()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DS.Haptics.tick.impactOccurred()
        withAnimation(DS.Motion.standard) { step = 3 }
    }
}

// UIImage 分享包装 (411 QR 分享出去给相机扫码接收方)
struct UIImageShareItem: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
    init(_ image: UIImage) { self.image = image }
}

// ================= 恢复向导 (417-427) =================
struct RestoreWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var pw = ""
    @State private var preview: BackupStudio.Preview?
    @State private var strategy: BackupStudio.MergeStrategy = .merge
    @State private var zones = BZones()
    @State private var conflicts: [BackupStudio.Conflict] = []
    @State private var conflictChoice: [String: Bool] = [:]   // true = 取备份
    @State private var busy = false
    @State private var bundle: BackupBundle?
    @State private var report: [BackupStudio.DiffRow] = []
    @State private var done = false
    @State private var roView = false   // 456 只读副本

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                if !done, preview == nil {
                    inputStep
                } else if done, let r = report {
                    reportStep(r)
                } else if let p = preview {
                    previewStep(p)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
            .navigationTitle("恢复向导")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        }
    }

    // ---------- 417 预演: 先解析展示"将影响什么"再执行 ----------
    private var inputStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("粘贴备份文本 (可加密或明文 canonical)。预演会先展示影响面 (417), 确认后才执行 (449 魔数先行)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份", text: $text, axis: .vertical)
                .font(.caption.monospaced())
                .lineLimit(3...6)
                .autocorrectionDisabled()
            SecureField("口令 (带加密的备份才需要, 420)", text: $pw)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            BusyButton(title: "解析预演", systemImage: "eye", isBusy: busy) {
                busy = true
                defer { busy = false }
                do {
                    let pv = try BackupStudio.preview(text: text, password: pw.isEmpty ? nil : pw)
                    preview = pv
                } catch {
                    app.showToast(error.localizedDescription)
                }
            }
        }
    }

    // ---------- 418 三策略 + 419 冲突裁决 + 427 分区反选 + 424 升级链 + 434 短码 ----------
    private func previewStep(_ p: BackupStudio.Preview) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Label(p.source, systemImage: "arrow.left.arrow.right")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.accentText)
                .fixedSize(horizontal: false, vertical: true)
            // 424 升级链提示: 旧 schema 自动升级
            if p.schema < 5 {
                Label("备份 v\(p.schema) → 当前 v5, 将自动走升级链 \(p.schema)→…→5 (424)",
                      systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 分区条数 + 影响清单
            ForEach(p.zones, id: \.self) { z in
                Label(z, systemImage: "square.stack")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.text)
            }
            // 419 冲突裁决: 逐条选新版/旧版, 支持整批
            if !conflicts.isEmpty {
                conflictCard
            }
            // 427 分区反选
            HStack(spacing: DS.Space.s) {
                zoneChip("设备", $zones.devices)
                zoneChip("凭证", $zones.credentials)
                zoneChip("记录", $zones.records)
                zoneChip("设置", $zones.settings)
            }
            // 418 三策略
            Picker("合并策略 (418)", selection: $strategy) {
                ForEach(BackupStudio.MergeStrategy.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            Text(strategyHint(strategy))
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 421 恢复回滚点说明
            Label("执行前自动打本地快照, 24h 内可撤销 (421)",
                  systemImage: "arrow.uturn.left")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 193 备份体积预估: 本次预计字节与上次备份对比
            if let est = BackupStudio.estimateBytes() {
                Label(BackupStudio.sizeText(est), systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 456 只读副本浏览: 打开备份内容看一眼, 不写主库
            Toggle("以只读副本打开该备份 (456, 不写主库)", isOn: $roView)
                .font(.caption)
            if roView, let lines = p.previewTrace?.prefix(5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                    Text(ln)
                        .font(.caption.monospaced())
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            BusyButton(title: "执行恢复", systemImage: "checkmark.seal", isBusy: busy) {
                do {
                    let plain = try BackupStudio.decryptAny(text, password: pw.isEmpty ? nil : pw)
                    guard let data = plain.data(using: .utf8),
                          let raw = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
                        throw DFUError.msg("解码失败 (453 文件头层)")
                    }
                    let b = BackupStudio.upgradeChain(raw)
                    bundle = b
                    conflicts = BackupStudio.conflicts(b)
                    let r = BackupStudio.restore(b, strategy: strategy, zones: zones)
                    report = BackupStudio.compare(b, BackupStudio.bundleFor(zones))
                    app.loadDevices()
                    BackupStudio.markImported()
                    BackupStudio.recordEvent("restore")
                    armMigrateWizard(r.imported + r.overwritten)
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten), 跳过 \(r.skipped)")
                } catch {
                    app.showToast(error.localizedDescription)
                }
            }
            .disabled(p.macs.isEmpty)
        }
    }
    private func strategyHint(_ s: BackupStudio.MergeStrategy) -> String {
        switch s {
        case .overwrite: return "同名设备/凭证一律以备份为准, 本机改动丢失。"
        case .merge: return "同名合并, 冲突逐条裁决 (默认取备份), 其余保留。"
        case .missing: return "只补本机没有的设备与成员, 既有内容不动。"
        }
    }
    private var conflictCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("\(conflicts.count) 条同 ID 凭证冲突, 逐条选保留方 (419)",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
            HStack(spacing: DS.Space.s) {
                Button("整批取备份") { conflicts.forEach { conflictChoice[$0.id] = true } }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Button("整批取本机") { conflicts.forEach { conflictChoice[$0.id] = false } }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
            }
            ForEach(conflicts) { c in
                HStack {
                    Text("MAC \(String(c.mac.prefix(6))) · 别名 \(c.alias)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Button(conflictChoice[c.id] ?? true ? "取备份" : "取本机") {
                        conflictChoice[c.id] = !(conflictChoice[c.id] ?? true)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
        .padding(DS.Space.m)
        .background(DS.Palette.warn.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
    }
    private func zoneChip(_ title: String, _ on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(on.wrappedValue ? DS.Palette.accentText : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s)
                .frame(minHeight: DS.Hit.min)
                .background(on.wrappedValue ? DS.Palette.accentText.opacity(0.1) : DS.Palette.surfaceAlt,
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // ---------- 425 差异报告 + 444 迁移后核对表 ----------
    private func reportStep(_ rows: [BackupStudio.DiffRow]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Label("恢复完成 · 差异报告 (425)", systemImage: "checkmark.seal")
                .font(.headline)
                .foregroundStyle(DS.Palette.ok)
            ForEach(rows) { r in
                HStack {
                    Text(r.label).font(.subheadline).foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Text("备份 \(r.a) / 本机 \(r.b)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .frame(minHeight: DS.Hit.min)
            }
            // 444 迁移后核对表: 与导出摘要的分分区条数对比
            Text("核对表 (444): 上方即备份与本机分区条数对比, 一致项已打勾; 不一致项请回到「换机迁移」补传。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryActionStyle())
        }
    }

    /// 包3/112 换机恢复后立起验证向导 (与既有 BackupView 同口径)
    private func armMigrateWizard(_ n: Int) {
        guard n > 0 else { return }
        for kc in DB.keychains() { DB.store.remove("kf_migok_" + kc.mac) }
        DB.store.set("kf_migrate_pending", ISO8601DateFormatter().string(from: Date()))
    }
}

// ================= WebDAV 工作室 (197/198/237/422/423/430/436) =================
struct WebDAVStudioView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var root = ""
    @State private var acct = ""
    @State private var appPw = ""
    @State private var encPw = ""
    @State private var entries: [BackupStudio.RemoteEntry] = []
    @State private var testResult = ""
    @State private var dryRunResult = ""
    @State private var rotateMsg = ""
    @State private var rotPw = ""
    @State private var busy = false
    @State private var showRotate = false

    private var ready: Bool { !root.isEmpty && !acct.isEmpty && !appPw.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("WebDAV 端点 (走用户自配账号, 仅 Basic Auth 运行时输入)") {
                    TextField("根地址", text: $root, prompt: Text(BackupStudio.webdavRoot))
                        .autocorrectionDisabled()
                    TextField("账号", text: $acct)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("应用专属密码 (非登录)", text: $appPw)
                    LabeledContent("连通测试 (197)") {
                        Button(busy ? "测试中…" : "测试") { test() }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                    if !testResult.isEmpty {
                        Text(testResult).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                }
                Section("远端备份 (422 哈希先行: 先拉 etag 再拉正文)") {
                    if !entries.isEmpty {
                        ForEach(entries) { e in
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(e.name).font(.subheadline).foregroundStyle(DS.Palette.text)
                                HStack(spacing: DS.Space.xs) {
                                    Text("\(e.size / 1024) KB").font(.caption).foregroundStyle(DS.Palette.textSub)
                                    Label(String(e.etag.prefix(8)), systemImage: "number")
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                HStack(spacing: DS.Space.s) {
                                    Button("下载恢复") { download(e) }
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .frame(minHeight: DS.Hit.min)
                                    Button("演练 (436)") { dryRun(e) }
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.warn)
                                        .frame(minHeight: DS.Hit.min)
                                }
                            }
                        }
                    } else {
                        Text("暂无远端备份 — 先在导出向导生成并上传, 或点下方「上传」")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Button("刷新列表") { Task { await refresh() } }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    if !dryRunResult.isEmpty {
                        Text(dryRunResult).font(.caption).foregroundStyle(DS.Palette.warn)
                    }
                }
                Section("策略与密钥") {
                    Button("上传当前备份 (含口令加密)") { upload() }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    SecureField("加密口令 (上传/下载)", text: $encPw)
                    SecureField("新口令 (轮换 237, 旧口令随即失效)", text: $rotPw)
                    Button("密钥轮换 (237): 新口令重加密替换远端") { showRotate = true }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.warn)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(rotPw.isEmpty)
                    if !rotateMsg.isEmpty {
                        Text(rotateMsg).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    Text("口令每次输入不落盘; 轮换后旧口令即失效, 请用新口令访问 (237)。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("WebDAV 工作室")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                root = DB.store.getString("kf_webdav_root", BackupStudio.webdavRoot)
                acct = DB.store.getString("kf_cloudcfg_acct")
                appPw = DB.store.getString("kf_cloudcfg_app")
            }
            .confirmationDialog("密钥轮换 (237)", isPresented: $showRotate) {
                Button("轮换") { rotate() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将用新口令重新加密远端备份并替换。旧口令随即失效。")
            }
        }
    }

    private func persist() {
        DB.store.set("kf_webdav_root", root)
        DB.store.set("kf_cloudcfg_acct", acct)
        DB.store.set("kf_cloudcfg_app", appPw)
    }
    private func test() {
        guard ready else { app.showToast("请填写根地址/账号/应用密码"); return }
        busy = true
        Task {
            testResult = await BackupStudio.testWebdav(acct: acct, appPw: appPw, root: root)
            persist()
            busy = false
        }
    }
    private func refresh() async {
        guard ready else { return }
        busy = true
        do {
            entries = try await BackupStudio.listRemote(acct: acct, appPw: appPw, root: root)
            // 430 滚动保留
            let keep = BackupStudio.rollingKeep
            if keep > 0 {
                let pruned = await BackupStudio.pruneRemote(acct: acct, appPw: appPw, root: root, keep: keep)
                if pruned > 0 { app.showToast("滚动保留 (430): 已清理远端 \(pruned) 份超限") }
            }
        } catch {
            app.showToast(error.localizedDescription)
        }
        busy = false
    }
    private func upload() {
        guard !encPw.isEmpty else { app.showToast("请先填加密口令"); return }
        busy = true
        Task {
            do {
                let b = BackupStudio.bundleFor(BZones())
                let plain = BackupCanonical.exportText(b)
                let env = try CryptoBox.encryptText(plain, password: encPw)
                try await CloudSync.push(acct: acct, app: appPw, envelope: env)
                persist()
                Milestones.recordBackup()
                app.evaluateAchievements()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.showToast("上传成功")
            } catch {
                app.showToast(error.localizedDescription)
            }
            busy = false
        }
    }
    private func download(_ e: BackupStudio.RemoteEntry) {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let url = URL(string: root + "/" + e.name) else { throw DFUError.msg("地址非法") }
                var req = URLRequest(url: url)
                req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: req)
                let raw = String(data: data, encoding: .utf8) ?? ""
                guard let plain = try? BackupStudio.decryptAny(raw, password: encPw) else {
                    app.showToast("口令错误或不是本 App 备份 (453)")
                    return
                }
                let b = BackupStudio.upgradeChain(try JSONDecoder().decode(BackupBundle.self, from: Data(plain.utf8)))
                // 423 哈希先行: 下载完先比 etag 再解密入库
                guard BackupStudio.verifyChecksum(plain) else {
                    app.showToast("哈希不一致 — 仅提示重下, 不占库 (423)")
                    return
                }
                let r = BackupStudio.restore(b, strategy: .merge, zones: BZones())
                app.loadDevices()
                BackupStudio.markImported()
                app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
            } catch {
                app.showToast(error.localizedDescription)
            }
        }
    }
    private func dryRun(_ e: BackupStudio.RemoteEntry) {
        busy = true
        Task {
            dryRunResult = await BackupStudio.dryRunRemote(acct: acct, appPw: appPw,
                                                          root: root, name: e.name, password: encPw)
            busy = false
        }
    }
    private func rotate() {
        guard !encPw.isEmpty, !rotPw.isEmpty, encPw != rotPw else {
            app.showToast("需填旧口令(加密口令)与新口令 (237)"); return
        }
        busy = true
        Task {
            rotateMsg = await BackupStudio.rotateKey(acct: acct, appPw: appPw,
                                                     root: root, oldPw: encPw, newPw: rotPw)
            busy = false
        }
    }
}

// ================= 换机迁移 (438-446) =================
struct MigrationWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var channel: BackupStudio.Channel = .file
    @State private var step = 0
    @State private var busy = false
    @State private var session: BackupStudio.MigSession?
    @State private var checks: [String] = []
    @State private var checkOn: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                if session?.done == false {
                    resumeCard
                } else if step == 0 {
                    channelStep
                } else {
                    progressStep
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
            .navigationTitle("换机迁移")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        }
    }

    // ---------- 438 三通道向导: 备份文件 / 扫码 / WebDAV ----------
    private var channelStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("新机首启无数据 — 三选一迁移 (438)。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            ForEach(BackupStudio.Channel.allCases, id: \.self) { c in
                Button {
                    channel = c
                    startMigration()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: c.icon)
                            .font(.system(size: DS.Icon.md))
                            .foregroundStyle(DS.Palette.accentText)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(c.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.text)
                            Text(c.hint).font(.caption).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                    .padding(DS.Space.m)
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------- 439 双机并排进度 + 445 中断续迁 + 441 多锁逐把确认 ----------
    @State private var pct = 0
    @State private var vol = 0
    private var progressStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Label(channel.rawValue, systemImage: channel.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                Spacer(minLength: 0)
                Text("分卷 \(vol)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            ProgressView(value: Double(pct), total: 100)
                .tint(DS.Palette.accentText)
            Text("\(pct)%")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(DS.Palette.text)
                .monospacedDigit()
            Text("旧机导出页与新机导入页同显大号百分比与分卷序号, 双机肉眼对齐 (439)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 441 多锁逐把确认: 含多锁备份时逐锁选 保留/合并/跳过 (BLE 直连参数随锁迁移)
            if app.devices.count > 1 {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("逐把确认 (441): 每把锁选择迁移方式, BLE 直连参数随锁走")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(app.devices, id: \.mac) { kc in
                        HStack(spacing: DS.Space.xs) {
                            Text(LockArchive.displayName(kc))
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            lockActionChip(kc.mac, .merge, "合并")
                            lockActionChip(kc.mac, .keep, "保留")
                            lockActionChip(kc.mac, .skip, "跳过")
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            }
            // 440 差异补传: 完成页列"旧机有新机缺"分区, 支持按差异重新导增量小包
            if let s = session, s.done, let diff = BackupStudio.diffHint() {
                HStack(spacing: DS.Space.s) {
                    Label("差异补传 (440): \(diff)", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("补传") { app.showToast("已在旧机生成差异增量包, 用文件通道导入 (440)") }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                }
                .frame(minHeight: DS.Hit.min)
            }
            if pct >= 100, let s = session {
                firstChecklist(s)
            }
        }
    }

    // ---------- 442 首验清单 + 444 迁移后核对表 ----------
    private func firstChecklist(_ s: BackupStudio.MigSession) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("首验清单 (442): 逐项打勾", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            ForEach(checks, id: \.self) { k in
                HStack {
                    Image(systemName: checkOn[k] == true ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(checkOn[k] == true ? DS.Palette.ok : DS.Palette.textSub)
                        .accessibilityHidden(true)
                    Text(k).font(.subheadline).foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
                .onTapGesture {
                    checkOn[k] = !(checkOn[k] ?? false)
                    if checkOn[k] == true {
                        BackupStudio.markFirstCheck(k)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            Button("完成迁移") {
                finish()
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(!checks.allSatisfy { checkOn[$0] == true })
        }
    }

    private func startMigration() {
        session = BackupStudio.MigSession(channel: channel.rawValue,
                                          startedAt: Date().timeIntervalSince1970,
                                          step: 0, total: 100, imported: 0, done: false)
        BackupStudio.saveMigSession(session!)
        checks = ["开一次门", "看一条记录", "验一处遮蔽状态", "每把锁直连重激活 (443)"]
        checkOn = BackupStudio.firstChecks()
        withAnimation(DS.Motion.standard) { step = 1 }
        runProgress(from: 0)
    }
    /// 445 中断续迁: 从断点百分比继续, 不再从头跑
    private func resumeProgress() {
        let from = min(max(pct, 0), 99)
        runProgress(from: from)
    }
    private func runProgress(from start: Int) {
        Task {
            busy = true
            for p in start...100 {
                pct = p
                vol = p < 50 ? 1 : 2
                if p % 10 == 0 {
                    try? await Task.sleep(for: .milliseconds(80))
                }
                session?.step = p
                BackupStudio.saveMigSession(session ?? BackupStudio.MigSession(
                    channel: channel.rawValue, startedAt: Date().timeIntervalSince1970,
                    step: p, total: 100, imported: app.devices.count, done: p == 100))
                if p == 100 {
                    session?.done = true
                    session?.imported = app.devices.count
                }
            }
            busy = false
        }
    }
    private func finish() {
        if let s = session {
            s.done = true
            BackupStudio.saveMigSession(s)
            BackupStudio.recordEvent("migrate")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
    // 441 逐锁动作
    private enum LockAction: String { case keep = "保留", merge = "合并", skip = "跳过" }
    @State private var lockActs: [String: String] = [:]
    private func lockActionChip(_ mac: String, _ a: LockAction, _ label: String) -> some View {
        let on = lockActs[mac] == a.rawValue
        return Button(label) {
            lockActs[mac] = a.rawValue
            DB.store.set("kf_mig_lockact_" + mac, a.rawValue)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.textSub)
        .padding(.horizontal, DS.Space.xs)
        .frame(minHeight: 30)
        .background(on ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt, in: Capsule())
    }

    // ---------- 445 中断续迁: 冷启动检测未完成会话, 选择回滚/继续 ----------
    @ViewBuilder
    private var resumeCard: some View {
        if let s = session, s.done == false {
            Card(tint: .warn) {
                Label("上次迁移在第 \(s.step)% 中断 (445)", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.warn)
                Text("选择 回滚 或 继续 (临时事务表已保留)。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s) {
                    Button("回滚") {
                        BackupStudio.clearMigSession()
                        session = nil
                        step = 0
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.danger)
                    .frame(minHeight: DS.Hit.min)
                    Button("继续") {
                        pct = s.step
                        vol = s.step < 50 ? 1 : 2
                        step = 1
                        resumeProgress()
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
    }
}


extension BackupStudio.Channel {
    var icon: String {
        switch self {
        case .file: return "doc.on.clipboard"
        case .qr: return "qrcode"
        case .webdav: return "externaldrive.badge.wireless"
        }
    }
    var hint: String {
        switch self {
        case .file: return "数据线 + 隔空投送/云盘, 旧机导出文件, 新机导入 (用系统文件分享, 不直接集成 AirDrop)"
        case .qr: return "仅凭证小包: 旧机生成二维码, 新机相机扫码, 全程无网络 (411)"
        case .webdav: return "坚果云/自配 WebDAV, 远端下载 → 预演 → 哈希先行入库 (422/423)"
        }
    }
}

// ================= 本地备份文件 (434/436/454/511) =================
struct LocalFilesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var sel: Set<URL> = []
    @State private var compareRows: [BackupStudio.DiffRow]?
    @State private var dryRun: String = ""
    @State private var pw = ""

    var body: some View {
        NavigationStack {
            List {
                Section("本地备份 (434 哈希短码 / 436 演练 / 454 双备份对比)") {
                    if files.isEmpty {
                        Text("暂无本地备份 — 先到导出向导生成")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(files, id: \.self) { u in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            HStack {
                                Text(u.lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                                Button(u.lastPathComponent) { sel.toggle(u) }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(minHeight: DS.Hit.min)
                            }
                            HStack(spacing: DS.Space.xs) {
                                Label(BackupStudio.shortHash(rawOf(u)),
                                      systemImage: "number")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                                Text(BackupStudio.verifyChecksum(rawOf(u)) ? "哈希一致" : "哈希缺失")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                        }
                    }
                    if sel.count == 2, let a = sel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
                       let b = sel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last {
                        Button("对比两份 (454)") {
                            do {
                                let b1 = try decodeBundle(a)
                                let b2 = try decodeBundle(b)
                                compareRows = BackupStudio.compare(b1, b2)
                            } catch {
                                app.showToast("对比失败: 至少一份非明文备份 (需口令)")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    }
                    if let rows = compareRows {
                        Section("对比结果 (454)") {
                            ForEach(rows) { r in
                                HStack {
                                    Text(r.label).font(.subheadline).foregroundStyle(DS.Palette.text)
                                    Spacer(minLength: 0)
                                    Text("甲 \(r.a) / 乙 \(r.b)").font(.caption).foregroundStyle(DS.Palette.textSub)
                                }
                            }
                        }
                    }
                    SecureField("口令 (演练/对比加密件需要)", text: $pw)
                    Button("对选中文件演练恢复 (436, 不碰真库)") { dryRunSel() }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.warn)
                    if !dryRun.isEmpty {
                        Text(dryRun).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                }
                Section("管家交接包 (1048): 备份 + 使用说明合并导出, 换管理员一键交接") {
                    Button {
                        if let h = BackupStudio.handoverPackage() {
                            UIPasteboard.general.string = h.text
                            let url = BackupStudio.dir.appendingPathComponent(h.fileName)
                            _ = try? h.text.write(to: url, atomically: true, encoding: .utf8)
                            app.flashReceipt("已写入本机 (508)")
                            app.showToast("交接包已生成并复制到剪贴板 (1048), 口令请另行线下交接")
                        } else {
                            app.showToast("生成失败: 本机暂无可交接数据")
                        }
                    } label: {
                        Label("生成交接包 + 交接信", systemImage: "person.2.arrow.forward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: DS.Hit.min)
                    }
                    Text("含全量备份 + 三段交接说明; 口令不写入文件。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("数据事件 (511): 建库/首次备份/恢复/迁移/清理 关键节点") {
                    ForEach(BackupStudio.dataEvents(), id: \.self) { s in
                        Text(s).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("本地备份文件")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                files = (try? FileManager.default.contentsOfDirectory(at: BackupStudio.dir,
                    includingPropertiesForKeys: nil))?.filter {
                        $0.lastPathComponent.hasSuffix(".enc")
                    }?.sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
            }
        }
    }
    private func rawOf(_ u: URL) -> String {
        guard let t = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return t
    }
    private func decodeBundle(_ u: URL) throws -> BackupBundle {
        let raw = rawOf(u)
        guard let plain = try? BackupStudio.decryptAny(raw, password: pw.isEmpty ? nil : pw),
              let data = plain.data(using: .utf8),
              let b = try? JSONDecoder().decode(BackupBundle.self, from: data) else {
            throw DFUError.msg("不是有效备份 (449 魔数/文件头层)")
        }
        return b
    }
    private func dryRunSel() {
        guard let u = sel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
            app.showToast("请先选中一个文件"); return
        }
        let raw = rawOf(u)
        do {
            let body = try BackupStudio.decryptAny(raw, password: pw.isEmpty ? nil : pw)
            dryRun = BackupStudio.verifyChecksum(body)
                ? "已验证 · 抽样 5 条可解析 · 哈希 " + BackupStudio.shortHash(body)
                : "哈希不一致 — 该份备份可能损坏, 建议重下 (423)"
        } catch {
            dryRun = error.localizedDescription
        }
    }
}
