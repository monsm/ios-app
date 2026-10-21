// 包8 备份工作室 UI — 备份·恢复·换机迁移 (五块: 导出向导/恢复/WebDAV与策略/换机迁移/完整性信任感)
// 纪律: 颜色只经 DS 令牌; 备份文件只去用户自配 WebDAV; 口令不出本机内存; 触达 ≥44pt。
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreImage
import VisionKit   // 411 扫码接收侧复用 CredentialStudio 522 的 DataScannerView (形状见 docs/API-VERIFY.md, 不猜改)

// ================= 入口: 工作室首页 =================
struct BackupStudioView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showExport = false
    @State private var showRestore = false

    var body: some View { vkBody.destined(.backupStudio) }
    var vkBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: XSpace.l) {
                    trustHeader
                    actionCards
                    cadenceCard
                }
                .padding(.vertical, XSpace.m)
            }
            .navigationTitle("备份工作室")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showExport) { ExportWizardView() }
            .sheet(isPresented: $showRestore) { RestoreWizardView() }
        }
    }

    // ---------- 512 数据主权声明 (盾形 SF Symbol + 固定一句) + 509 双向天数行 ----------
    private var trustHeader: some View {
        Card(tint: .ok) {
            HStack(spacing: XSpace.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: XIcon.lg, weight: .semibold))
                    .foregroundStyle(XPalette.ok)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("数据只存在这台 iPhone")   // 512 数据只存在这台
                        .vkFont(.headline)
                        .foregroundStyle(XPalette.text)
                    HStack(spacing: XSpace.s) {
                        Label(daysText("上次导出", BackupStudio.daysSinceLastExport()),
                              systemImage: "square.and.arrow.up")
                        Label(daysText("上次导入", BackupStudio.daysSinceLastImport()),
                              systemImage: "square.and.arrow.down")
                    }
                    .vkFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .accessibilityElement(children: .combine)
                    // 37 备份加密徽章 (Proton): 算法参数外露, 换算法后旧文件各自标注
                    Label("AES-128-CBC + HMAC-SHA256 · PBKDF2 60000 轮 — 徽章是「当前代码」用的算法; "   // 37 AES
                          + "每份旧备份自己的参数在「本地备份文件」列表逐文件标注",   // 435 每份旧备份自己的参数
                          systemImage: "lock.shield.fill")
                        .vkFont(.caption2)
                        .foregroundStyle(XPalette.ok)
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
                    .vkFont(.caption)
                    .foregroundStyle(XPalette.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 421 24h 内可撤销本次恢复
            if BackupStudio.canUndoLastRestore {
                Button {
                    confirmDestructive("撤销本次恢复", "将回到恢复前自动打的快照。只回写快照里已有的内容，"   // 421 将回到恢复前自动打的
                    + "快照之后你新写的备注、新钉的复核日不会被删掉。确定吗？",
                                        confirmTitle: "撤销") {
                        if BackupStudio.undoLastRestore() {
                            app.loadDevices()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            app.showToast("已撤销本次恢复")   // 421 已撤销本次恢复
                        } else {
                            app.showToast("撤销失败: 快照不可读")
                        }
                    }
                } label: {
                    Label("撤销本次恢复 (24h 内)", systemImage: "arrow.uturn.left")
                        .vkFont(.subheadline)
                        .foregroundStyle(XPalette.danger)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: XHit.min)
                        .background(XPalette.danger.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
                }
            }
        }
    }
    private func daysText(_ label: String, _ d: Int) -> String {
        d < 0 ? "\(label) 暂无" : (d == 0 ? "\(label) 今日" : "\(label) \(d) 天前")
    }
    private var freshnessBanner: some View {
        HStack(spacing: XSpace.s) {
            Text("距上次备份已 \(BackupStudio.daysSinceLastExport()) 天")   // 429 距上次备份已
                .vkFont(.caption)
                .foregroundStyle(XPalette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("立即备份") { showExport = true }
                .vkFont(.caption, weight: .semibold)
                .foregroundStyle(XPalette.accentText)
                .frame(minHeight: XHit.min)
        }
        .padding(.top, XSpace.s)
    }

    // ---------- 五大动作卡 (触达 ≥44pt) ----------
    private var actionCards: some View {
        VStack(spacing: XSpace.s) {
            studioRow(title: "导出向导", sub: "分区勾选 · 口令 · 自描述命名 · 二维码搬运",
                      icon: "tray.and.arrow.up", tint: XPalette.accentText) { showExport = true }
            studioRow(title: "恢复向导", sub: "预演 · 三策略 · 冲突裁决 · 回滚点",
                      icon: "tray.and.arrow.down", tint: XPalette.warn) { showRestore = true }
        }
    }
    private func studioRow(title: String, sub: String, icon: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XSpace.m) {
                Image(systemName: icon)
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    Text(title)
                        .vkFont(.subheadline, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    Text(sub)
                        .vkFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: XSpace.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: XIcon.xs))
                    .foregroundStyle(XPalette.textSub)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: XHit.min)
            .padding(XSpace.l)
            // 2026-10-14 材质统一: 通道入口行是坐在页面底上的面板 (它下面就是 gutter)，与同页
            // 三选一卡、预演分段块同材质。这处原本写成两行 `.background(surface,\n in: …)`，
            // 单行正则扫不到 —— 现在信 AST 那条 R6，不信 grep。
            .axGlass(XRadius.card)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, XSpace.gutter)
        .accessibilityElement(children: .combine)
    }

    // ---------- 198 节奏三档 + 430 滚动保留 + 1018 月度备份日 + 428 充电 ----------
    @State private var cadence: String = ""
    // 713 固定导出目录: 选择器开关 + 改完强制重算一次 (书签是 DB 里的值, 不 tick 不会重画)
    @State private var showDirPicker = false
    @State private var dirTick = 0
    @State private var keep: Int = 0
    @State private var monthDay: Int = 0
    private var cadenceCard: some View {
        Card {
            SectionTitle(text: "备份策略")
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("备份节奏", selection: Binding(   // 198 备份节奏
                get: { cadence.isEmpty ? BackupStudio.cadence : cadence },
                set: { BackupStudio.cadence = $0; cadence = $0
                       Task { await BackupStudio.scheduleCadenceReminder() } })) {
                Text("仅手动").tag("manual")
                Text("每周").tag("weekly")
                Text("每月").tag("monthly")
            }
            .pickerStyle(.segmented)
            Stepper("滚动保留: 远端只留 \(keep) 份", value: Binding(   // 430 滚动保留
                get: { keep },
                set: { BackupStudio.rollingKeep = $0; keep = $0 }), in: 0...20)
            // 删除面必须写在界面上：默认远端目录就是整个坚果云，用户以为「只留 N 份」只管自己的备份，
            // 而这一句决定他敢不敢开这个开关 (判据与理由见 BackupStudioKit.pruneRemote 上方)。
            // 2026-10-15 走查: 同一档 rollingKeep 还会轮换**本机**导出目录 (pruneLocal, 只在真写成新备份后触发),
            // 那件事此前只在导出完成的那句回执里说 —— 事后说清 ≠ 事前说清, 开关上手那一刻就得写明。
            Text("只清理本 App 生成的备份文件 (文件名以「锁管家_」开头那族)，目录里的其它文件与子目录一律不动；0 = 不限。同一档也用于本机导出目录的轮换 (每次成功导出之后)。")
                .vkFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 713 固定导出目录: 用安全作用域书签记住用户选的文件夹, 之后每次导出都落那里 ——
            // 没设过时回落 App 缓存目录 (系统可能清理), 所以这里把两种落点都写清。
            let _ = dirTick
            HStack(spacing: XSpace.s) {
                VStack(alignment: .leading, spacing: XSpace.xxs) {
                    Text("导出目录")   // 713 导出目录
                        .vkFont(.subheadline, weight: .medium)
                    Text(ExportDir.name.isEmpty
                         ? "未设置 — 导出落在 App 缓存目录 (系统可能清理)"
                         : "已固定: \(ExportDir.name)")
                        .vkFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                }
                Spacer(minLength: 0)
                Button(ExportDir.name.isEmpty ? "选择" : "更换") { showDirPicker = true }
                    .vkFont(.footnote)
                    .foregroundStyle(XPalette.accentText)
                    .frame(minHeight: XHit.min)
                if !ExportDir.name.isEmpty {
                    Button("清除") { ExportDir.clear(); dirTick += 1 }
                        .vkFont(.footnote)
                        .foregroundStyle(XPalette.danger)
                        .frame(minHeight: XHit.min)
                }
            }
            .frame(minHeight: XHit.min)
            .fileImporter(isPresented: $showDirPicker, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r { ExportDir.set(u); dirTick += 1 }
            }
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("月度备份日: \(monthDay == 0 ? "关" : "每月 \(monthDay) 日")",   // 1018 月度备份日
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
            VariantToggle("充电时自动备份",   // 428 充电时自动备份
                   isOn: Binding(
                    get: { DB.store.getBool("kf_bk_bgtask") },
                    set: { on in
                        DB.store.set("kf_bk_bgtask", on)
                        if on {
                            // 2026-10-14: 注册已在启动时完成, 这里只排期 (启动后 register 会崩)。
                            BackupStudio.rescheduleChargeBackup()
                            app.showToast(BackupStudio.chargeBackupNote)
                        }
                    }))
            if DB.store.getBool("kf_bk_bgtask") {
                Text(BackupStudio.chargeBackupNote)
                    .vkFont(.caption)
                    .foregroundStyle(XPalette.textSub)
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

// ---------- 445/446 旧机顶部卡: 中断事务 → 退役引导 → 已退役存档 ----------


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


// ================= WebDAV 工作室 (197/198/237/422/423/430/436) =================




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
        case .file: return "旧机导出 .enc 后经数据线/隔空投送/云盘传到本机, 这里粘贴或从「文件」选择接收"   // 438 旧机导出
        case .qr: return "仅凭证小包 (口令信封): 旧机导出页生成二维码, 本页相机扫码 + 同一口令导入, 全程无网络"   // 411/438 仅凭证小包 (口令信封)
        case .webdav: return "坚果云/自配 WebDAV: 读远端列表 → 下载 → 解析入库, 两台机不见面也能迁"   // 422/423 坚果云
        }
    }
}

/// 411 扫码接收端 (新机侧): 扫旧机 导出向导 完成页的凭证二维码 → 原文交给换机迁移接收队列。
/// ⚠ CredentialStudio.swift 里 DataScannerView 的调用形状禁止改写 — 它已挂在 docs/API-VERIFY.md:
/// 「撞不到 Apple 文档、形状高度可疑、在编译器看过之前不许凭记忆重写」。本页只接接收侧流程
/// (拿到原文 → 上层 417/453 解密解析入库), 调用形态逐字复用 522 的那一处, 不做任何猜改。

// ================= 本地备份文件 (434/436/454/511) =================


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
    @State private var doneURLs: [URL] = []
    @State private var qrPayload: String?
    // 411 P0: 二维码不再是明文母钥包。没口令就不出码; 完成页可单独设一个二维码口令。
    @State private var qrPass = ""
    @State private var qrMsg = ""
    @State private var otpToggle = false
    // 439 旧机导出侧真进度: 百分比与分卷序号只随真做完的阶段前进
    @State private var exporting = false
    @State private var exportPct = 0
    @State private var exportVol = 0
    @State private var exportVolTotal = 1
    // 440 增量补传 (旧机侧): 按锁勾选生成小包
    @State private var incSel: Set<String> = []
    @State private var incURL: URL?
    @State private var incMsg = ""

    private let stepTitles = ["选分区", "设口令", "导出前体检", "完成"]

    var body: some View { vkBody.destined(.exportWizard) }
    var vkBody: some View {
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
                            .vkFont(.subheadline)
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
                       "门锁钥匙串 + BLE 直连参数")   // 441 门锁钥匙串
            zoneToggle("凭证", counts["凭证"] ?? 0, $zones.credentials,
                       "密码与指纹台账")
            zoneToggle("记录", counts["记录"] ?? 0, $zones.records,
                       // 2026-10-15 走查: 原文案「锁端日志缓存 (按锁约) · N 份缓存」两头都是假的 ——
                       // 锁端日志不进备份包, 这一档裁的是 globals.trace 那一份本机写入轨迹。
                       "本机记录写入轨迹 · 锁端日志缓存根本不进备份包 (要看锁里的记录得到记录页现读)", unit: "份")
            zoneToggle("设置", counts["设置"] ?? 0, $zones.settings,
                       "成员档案 · 应用锁摘要 · dongle/gateway")
            VariantToggle("包含独立口令组密钥",   // 181 包含独立口令组密钥
                   isOn: $otpToggle)
                .help("勾选后 TOTP 种子/静态码进**备份包体内部**: 随整包口令加密、进校验和、恢复时能读回来。未勾则完全不进包体。仅在勾选\"设置\"分区时生效。")
                .onAppear { otpToggle = BackupStudio.otpIncluded() }
                .onChange(of: otpToggle) { _, on in DB.store.set("kf_bk_otp", on) }
            if useVolumes, let vols = BackupStudio.volumes(zones: zones, encrypt: nil) {
                Text("记录区超阈值, 将拆为 \(vols.count) 卷: 基础卷 + 逐年记录卷, 各卷可独立恢复。")   // 410 记录区超阈值
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    private func zoneToggle(_ title: String, _ n: Int, _ on: Binding<Bool>, _ sub: String, unit: String = "条") -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            VariantToggle(isOn: on) {
                HStack(spacing: DS.Space.s) {
                    Text(title)
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                    Text("\(n) \(unit)").vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: DS.Hit.min, alignment: .center)
            Text(sub)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s)
        .variantPlate(DS.Palette.surfaceAlt, .tile)
        .accessibilityElement(children: .combine)
    }

    // ---------- 第 1 步: 408 口令两遍 (纯数字/过短只提醒不拦截) ----------
    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("两遍输入加密口令。可留空 = 不加密 (明文 canonical, 与小程序互通)。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("口令", text: $pw)
                .vkFont(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DS.Space.s)
                // @layout-allow VK豁免 控件可识别性: SecureField 的底衬：去掉它，屏幕上冒出一个没有任何边界的输入框
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            SecureField("再输一遍", text: $pw2)   // 408 再输一遍
                .vkFont(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DS.Space.s)
                // @layout-allow VK豁免 控件可识别性: SecureField 的底衬：去掉它，屏幕上冒出一个没有任何边界的输入框
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            if !pw.isEmpty && pw != pw2 {
                Text("两次输入不一致")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.danger)
            } else if !pw.isEmpty && DB.verifyPasscode(pw) {
                // 549 口令复用检测: 备份口令与应用锁密码相同 → 提示分开设置
                Text("此口令与应用锁密码相同 — 建议两者分开设置。")   // 549 此口令与应用锁密码相
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !pw.isEmpty && (pw.count < 8 || pw.allSatisfy(\.isNumber)) {
                Text("纯数字或过短口令偏弱 — 不拦截, 仅提醒。")   // 408 纯数字或过短口令偏弱
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // ---------- 第 2 步: 412/431 体检 + 清理联动 + 439 真导出进度 ----------
    private var healthStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("导出前体检: 统计摘要与问题清单。")   // 412 导出前体检
                .vkFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Palette.text)
            // 439 大号百分比 + 分卷序号: 与换机迁移的新机导入页同一对读数, 双机肉眼对齐
            if exporting {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("\(exportPct)%")
                        .vkFont(.largeTitle, weight: .heavy)
                        .foregroundStyle(DS.Palette.text)
                        .monospacedDigit()
                    Text(exportVol == 0 ? "组包与加密中…" : "分卷 \(exportVol)/\(exportVolTotal)")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ProgressView(value: Double(exportPct), total: 100)
                        .tint(DS.Palette.accentText)
                }
            }
            let rows = BackupStudio.preExportHealth()
            if rows.isEmpty {
                Label("数据健康, 可直接导出", systemImage: "checkmark.seal")
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.ok)
            } else {
                ForEach(rows) { h in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Text(h.label)
                            .vkFont(.subheadline, weight: .medium)
                            .foregroundStyle(DS.Palette.warn)
                        Text(h.text)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VariantToggle("先清理过期临时码再导出 (将减少 \(BackupStudio.expiredTemporaryCount()) 条)",
                   isOn: $cleanFirst)
            VariantToggle("按年分卷", isOn: $useVolumes)   // 410 按年分卷
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
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("已写入本机")   // 508 已写入本机
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                        Text(doneText)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .animation(DS.Motion.standard, value: doneText.isEmpty)
            }
            // 413 完成即分享 (ShareLink 系统面板 + 存储到文件快捷); 410 分卷时每卷各一枚
            ForEach(doneURLs, id: \.self) { url in
                ShareLink(item: url, preview: SharePreview("离线锁管家备份")) {
                    Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                }
            }
            // 411 二维码搬运: 只出**口令信封**, 不再出明文 canonical (P0, 2026-10-20)。
            // 接收端把扫到的原文交给 parsePreview(password:), 与加密备份走同一条解密链。
            if !useVolumes {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("凭证二维码(加密): 另一台手机打开 备份工作室→换机迁移→扫码, 输入同一口令才能导入; 全程无网络。")   // 411 凭证二维码(加密)
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    if let q = qrPayload, let img = BackupStudio.qrImage(q) {
                        ShareLink(item: UIImageShareItem(img), preview: SharePreview("凭证二维码"))
                        Text("这张码本身是口令信封: 截到码也打不开。但口令请当面或走另一条渠道, 不要和码一起发。")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(qrMsg.isEmpty ? "要用二维码搬运, 先设一个二维码口令 (至少 6 位)。" : qrMsg)
                            .vkFont(.caption2)
                            .foregroundStyle(qrMsg.isEmpty ? DS.Palette.textSub : DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        SecureField("二维码口令", text: $qrPass)
                            .vkFont(.caption)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("生成加密二维码") {
                            let strong = qrPass.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard strong.count >= 6 else { qrMsg = "口令太短: 二维码会被截图, 至少 6 位。"; return }
                            if let q = BackupStudio.credentialQRPayload(password: strong) {
                                qrPayload = q
                                qrMsg = ""
                            } else {
                                qrMsg = "凭证太多或生成失败, 一张二维码装不下 — 请用文件通道。"
                            }
                        }
                        .vkFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(qrPass.count < 6)
                    }
                }
            }
            // 440 增量补传 (旧机侧): 新机对账报"缺的锁"后, 在旧机只把缺的锁重新打包
            if !DB.keychains().isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("增量补传: 勾选要补的锁, 生成增量小包 (不含记录卷), 传到新机再走一次导入。")   // 440 增量补传
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(DB.keychains(), id: \.mac) { kc in
                        Button {
                            if incSel.contains(kc.mac) {
                                incSel.remove(kc.mac)
                            } else {
                                incSel.insert(kc.mac)
                            }
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: incSel.contains(kc.mac) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(incSel.contains(kc.mac) ? DS.Palette.ok : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                                Text(LockArchive.displayName(kc))
                                    .vkFont(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(DB.ledger(kc.mac).pwds.count + DB.ledger(kc.mac).fps.count) 条")
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            .frame(minHeight: DS.Hit.min)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("生成增量小包 (已勾 \(incSel.count) 把锁)") { makeIncremental() }
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(incSel.isEmpty)
                    if let u = incURL {
                        ShareLink(item: u, preview: SharePreview("离线锁管家增量包")) {
                            Text("分享 \(u.lastPathComponent)")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    if !incMsg.isEmpty {
                        Text(incMsg)
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("再生成一份") {
                qrPayload = nil
                qrPass = ""
                qrMsg = ""
                doneText = ""
                doneURLs = []
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
        exporting = true
        exportPct = 0
        exportVol = 0
        exportVolTotal = 1
        doneURLs = []
        let name = BackupStudio.fileName()
        let crypt = pw.isEmpty ? nil : pw
        Task {
            if cleanFirst { _ = BackupStudio.cleanExpired() }
            // 439 阶段 1 (真实工作): 组包 — 410 分卷与加密都发生在这里
            let vols = useVolumes ? BackupStudio.volumes(zones: zones, encrypt: crypt) : nil
            exportVolTotal = max(vols?.count ?? 1, 1)
            try? await Task.sleep(for: .milliseconds(80))
            var written: [URL] = []
            var volFail = 0
            if let vols = vols {
                // 439: 每写完一卷才前进一步, 分卷序号同真
                for (i, v) in vols.enumerated() {
                    let url = BackupStudio.dir.appendingPathComponent(BackupStudio.fileName(vol: v.index))
                    if (try? v.text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                        written.append(url)
                    } else {
                        volFail += 1
                    }
                    exportVol = i + 1
                    exportPct = Int(Double(i + 1) / Double(exportVolTotal) * 100)
                    try? await Task.sleep(for: .milliseconds(80))
                }
                qrPayload = nil
            } else {
                if let text = BackupStudio.exportText(zones: zones, encrypt: crypt),
                   let url = BackupStudio.writeLocal(text, name: name) {
                    written.append(url)
                    BackupStudio.markExportSize(text)   // 193: 单卷导出记尺寸, 下次预估行对比用
                    // 只有用户已经设了导出/备份口令才自动出码; 没设就留空, 由完成页要求单独输入。
                    qrPayload = pw.isEmpty ? nil : BackupStudio.credentialQRPayload(password: pw)
                    qrMsg = (pw.isEmpty || qrPayload != nil) ? "" : "凭证太多, 一张二维码装不下 — 请用文件通道。"
                }
                exportVol = 1
                exportPct = 100
                try? await Task.sleep(for: .milliseconds(80))
            }
            if written.isEmpty {
                exporting = false
                busy = false
                app.showToast("导出失败: 没有写出任何文件")
                return
            }
            doneURLs = written
            doneText = vols == nil
                ? "已写入 \(written.first?.lastPathComponent ?? name)。"   // 413 已写入
                : "已按年拆为 \(written.count) 卷: 基础卷 + 逐年记录卷, 各卷可独立恢复。"   // 410 已按年拆为
            if volFail > 0 { doneText += " 另有 \(volFail) 卷写盘失败。" }
            // 430 本地滚动保留: 只在**这次真的写成了新备份**之后轮换, 与远端那枚共用 rollingKeep 同一档 (0 = 关)。
            // 触发点不放列表页 onAppear —— 打开看一眼就删用户的文件是仓里明令禁止的那种实现。
            let prunedLocal = BackupStudio.pruneLocal(keep: BackupStudio.rollingKeep)
            if prunedLocal > 0 {
                doneText += " 按「本地只留 \(BackupStudio.rollingKeep) 份」轮换, 清掉 \(prunedLocal) 个旧文件。"   // 430 本地只留
            }
            // 507 角标 + 511 事件 (分卷路径旧实现漏记, 一并统一)
            BackupStudio.recordEvent("导出备份")
            Milestones.recordBackup()
            app.evaluateAchievements()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DS.Haptics.tick.impactOccurred()
            exporting = false
            busy = false
            withAnimation(DS.Motion.standard) { step = 3 }
        }
    }

    /// 440 增量补传 (旧机侧): 勾选的锁打成小包写盘, 记 511 事件
    private func makeIncremental() {
        guard !incSel.isEmpty else { return }
        guard let t = BackupStudio.incrementalExportText(macs: incSel, zones: zones, encrypt: pw.isEmpty ? nil : pw) else {
            incMsg = "没有可打包的锁或编码为空"
            return
        }
        let url = BackupStudio.writeLocal(t, name: BackupStudio.incrementalFileName())
        incURL = url
        if url == nil {
            incMsg = "写盘失败 — 检查存储空间后重试"
        } else {
            incMsg = "已写入本地备份文件列表 — 传到新机后用「换机迁移」任一通道导入"
            BackupStudio.recordEvent("导出增量补传")
        }
    }
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
    // 453 失败分层: 口令/文件头/哈希三层里的哪一层没过 — 卡片展示, 不用转瞬即逝的 toast
    @State private var layerError: String?
    // 425 三数: restore 返回的真实处置数
    @State private var impN = 0
    @State private var ovN = 0
    @State private var skN = 0

    var body: some View { vkBody.destined(.restoreWizard) }
    var vkBody: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                if !done, preview == nil {
                    inputStep
                } else if done {
                    // 2026-10-13 run 63: 原写 `else if done, let r = report` —— report 是
                    // `@State [BackupStudio.DiffRow]` (**非可选**), 可选绑定报
                    // "initializer for conditional binding must have Optional type, not '[BackupStudio.DiffRow]'"。
                    reportStep(report)
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
            // 449 粘贴备份文本
            Text("粘贴备份文本 (可加密或明文 canonical)。预演会先展示影响面, 确认后才执行。")   // 417 粘贴备份文本
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份", text: $text, axis: .vertical)
                .vkFont(.caption.monospaced())
                .lineLimit(3...6)
                .autocorrectionDisabled()
            SecureField("口令 (带加密的备份才需要)", text: $pw)
                .vkFont(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            BusyButton(title: "解析预演", systemImage: "eye", isBusy: busy) {
                busy = true
                defer { busy = false }
                do {
                    // 453: 预演即过三层检查 — 口令层解密、文件头层解码、哈希层比对
                    let r = try BackupStudio.parsePreview(text: text, password: pw.isEmpty ? nil : pw)
                    preview = r.preview
                    bundle = r.bundle
                    // 419: 冲突在预演阶段就列出来 (旧实现直到执行的同一帧才算, 卡片永远不显示)
                    conflicts = BackupStudio.conflicts(r.bundle)
                    for c in conflicts where conflictChoice[c.id] == nil { conflictChoice[c.id] = true }
                    layerError = nil
                } catch {
                    layerError = error.localizedDescription
                }
            }
            if let e = layerError {
                layerCard(e)
            }
        }
    }
    /// 453 分层失败卡: 把三层里实际没过的那层与建议摆在原地
    private func layerCard(_ e: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Label("解析/执行未通过", systemImage: "exclamationmark.triangle")   // 453 解析
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.warn)
            Text(e)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .variantCallout(DS.Palette.warn, .tile, wash: 0.06)
    }

    // ---------- 418 三策略 + 419 冲突裁决 + 427 分区反选 + 424 升级链 + 453 分层 + 434 短码 ----------
    private func previewStep(_ p: BackupStudio.Preview) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Label(p.source, systemImage: "arrow.left.arrow.right")
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.accentText)
                .fixedSize(horizontal: false, vertical: true)
            // 424 升级链: 逐级列出将要走的步骤 (执行侧 upgradeChain 同顺序同条数)
            let steps = BackupStudio.upgradeSteps(from: p.schema)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Label("旧 schema 自动升级链: v\(p.schema) → v5, \(steps.count) 级", systemImage: "arrow.up.circle")   // 424 自动升级链
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    ForEach(steps) { s in
                        Text("v\(s.from) → v\(s.to): \(s.note)")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // 453 哈希层状态: 解析已过前两层, 这一行的三种状态在预演时就能说清
            switch p.checksum {
            case .ok:
                Label("文件三层检查: 口令层已解 · 文件头已认 · 内容哈希一致", systemImage: "checkmark.seal")   // 453 文件三层检查
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.ok)
            case .absent:
                Label("该备份没有校验和字段 (旧包/人工编辑) — 按兼容放行, 内容被改过时无法预警",   // 453 该备份没有校验和字段
                      systemImage: "exclamationmark.triangle")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            case .mismatch:
                Label("内容哈希不一致 — 已在解析时拦下", systemImage: "xmark.seal")   // 453 内容哈希不一致
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.danger)
            }
            // 分区条数 + 影响清单
            ForEach(p.zones, id: \.self) { z in
                Label(z, systemImage: "square.stack")
                    .vkFont(.subheadline)
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
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("合并策略", selection: $strategy) {   // 418 合并策略
                ForEach(BackupStudio.MergeStrategy.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            Text(strategyHint(strategy))
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 418: 量级预估行 (包内条数 + 同 ID 冲突数), 选策略前先知道规模
            Text("预估: 本包 \(p.pwdCount) 密码/\(p.fpCount) 指纹, 同 ID 冲突 \(conflicts.count) 条")   // 418 预估
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            // 421 恢复回滚点说明
            Label("执行前自动打本地快照, 24h 内可撤销",   // 421 执行前自动打本地快照
                  systemImage: "arrow.uturn.left")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 193 备份体积预估: 本次预计字节与上次备份对比
            if let est = BackupStudio.estimateBytes() {
                Label(BackupStudio.sizeText(est), systemImage: "square.and.arrow.down")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 456 只读副本浏览: 打开备份内容看一眼, 不写主库 (锁列表 + 随机抽 5 条记录)
            VariantToggle("以只读副本打开该备份", isOn: $roView)   // 456 以只读副本打开该备份
                .vkFont(.caption)
            if roView, let b = bundle {
                ForEach(b.devices, id: \.mac) { d in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "lock.fill")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityHidden(true)
                        Text(LockArchive.displayName(d.kc))
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\((d.ledger?.pwds.count ?? 0) + (d.ledger?.fps.count ?? 0)) 条凭证 · \(d.meta == nil ? "无运行参数" : "含运行参数")")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            if roView, let lines = p.previewTrace?.prefix(5), !lines.isEmpty {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                    Text(ln)
                        .vkFont(.caption.monospaced())
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            if let e = layerError {
                layerCard(e)
            }
            BusyButton(title: "执行恢复", systemImage: "checkmark.seal", isBusy: busy) {
                busy = true
                defer { busy = false }
                do {
                    // 453: 三层全过才动库 — 口令层/文件头层/哈希层都走这一个入口
                    let r = try BackupStudio.parsePreview(text: text, password: pw.isEmpty ? nil : pw)
                    let b = r.bundle
                    bundle = b
                    conflicts = BackupStudio.conflicts(b)
                    for c in conflicts where conflictChoice[c.id] == nil { conflictChoice[c.id] = true }
                    // 419: 卡片上逐条选定的保留方真送进 restore 入参 (未裁决按显示默认 = 取备份)
                    var take = Set<String>()
                    for c in conflicts where (conflictChoice[c.id] ?? true) { take.insert(c.id) }
                    let res = BackupStudio.restore(b, strategy: strategy, zones: zones,
                                                   conflictTakeBackup: take)
                    impN = res.imported; ovN = res.overwritten; skN = res.skipped
                    if b.globals?.appearance != nil && zones.settings { app.reloadAppearance() }   // 894 按分区
                    report = BackupStudio.compare(b, BackupStudio.bundleFor(zones))
                    app.loadDevices()
                    BackupStudio.markImported()
                    BackupStudio.recordEvent("恢复本机")
                    armMigrateWizard(res.imported + res.overwritten)
                    done = true
                    layerError = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    app.showToast("恢复完成: 新增 \(res.imported), 覆盖 \(res.overwritten), 跳过 \(res.skipped)")
                } catch {
                    layerError = error.localizedDescription
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
            Label("\(conflicts.count) 条同 ID 冲突 — 逐条选保留哪边",   // 419 条同
                  systemImage: "arrow.triangle.2.circlepath")
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s) {
                Button("整批取备份") { conflicts.forEach { conflictChoice[$0.id] = true } }
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Button("整批取本机") { conflicts.forEach { conflictChoice[$0.id] = false } }
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
            }
            ForEach(conflicts) { c in
                HStack(spacing: DS.Space.xs) {
                    Text("\(c.kind) #\(c.alias) · \(String(c.mac.prefix(6)))")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    sideChip(c.id, false, "本机")
                    sideChip(c.id, true, "备份")
                }
                .frame(minHeight: DS.Hit.min)
            }
        }
        .padding(DS.Space.m)
        .variantCallout(DS.Palette.warn, .tile, wash: 0.06)
    }
    /// 419 逐条裁决芯片: 左边本机, 右边备份; 点哪边保留哪边
    private func sideChip(_ id: String, _ backupSide: Bool, _ label: String) -> some View {
        let on = (conflictChoice[id] ?? true) == backupSide
        return Button(label) {
            conflictChoice[id] = backupSide
        }
        .vkFont(.caption2, weight: .medium)
        .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.textSub)
        .padding(.horizontal, DS.Space.xs)
        .frame(minHeight: 30)
        .background(on ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt, in: Capsule())
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
    private func zoneChip(_ title: String, _ on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            Text(title)
                .vkFont(.caption, weight: .medium)
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
            Label("恢复完成 · 差异报告", systemImage: "checkmark.seal")   // 425 恢复完成
                .vkFont(.headline)
                .foregroundStyle(DS.Palette.ok)
            // 425 三数: 来自 restore 返回值的真实处置数 (旧报告只有 备份X/本机Y)
            HStack(spacing: DS.Space.l) {
                countChip("新增", impN, DS.Palette.ok)
                countChip("覆盖", ovN, DS.Palette.accentText)
                countChip("跳过", skN, DS.Palette.warn)
            }
            ForEach(rows) { r in
                HStack(spacing: DS.Space.s) {
                    // 444 核对表: 一致打勾, 不一致给提醒 (旧文案说"已打勾"但从未画过勾)
                    Image(systemName: r.a == r.b ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(r.a == r.b ? DS.Palette.ok : DS.Palette.warn)
                        .accessibilityHidden(true)
                    Text(r.label).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Text("备份 \(r.a) / 本机 \(r.b)")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .frame(minHeight: DS.Hit.min)
            }
            // 417 记录时间域: 备份内记录跨度 (trace 行首 16 字符 = yyyy-MM-dd HH:mm), 只读快照
            if let t = preview?.previewTrace, !t.isEmpty {
                Text("记录时间域: \(t.first?.prefix(16) ?? "") ~ \(t.last?.prefix(16) ?? "")")   // 417 界面文案
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            // 425 展开: 逐锁对账 — 备份里每把锁 vs 本机现况, 缺的锁点名
            if let b = bundle, !b.devices.isEmpty {
                DisclosureGroup {
                    ForEach(BackupStudio.lockDiffRows(b)) { d in
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: d.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.system(size: DS.Icon.xs))
                                .foregroundStyle(d.ok ? DS.Palette.ok : DS.Palette.warn)
                                .accessibilityHidden(true)
                            Text(d.label)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("备份 \(d.backup) / 本机 \(d.local) · \(d.note)")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    Text("逐锁对账 (\(b.devices.count) 把)")
                        .vkFont(.caption, weight: .medium)
                        .foregroundStyle(DS.Palette.text)
                }
            }
            // 444 迁移后核对表
            Text("核对表: 对勾 = 该项备份与本机条数一致; 缺的锁可到旧机「导出向导→完成页」用增量补传只勾缺的锁重打小包。")   // 444 核对表
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryActionStyle())
        }
    }
    private func countChip(_ label: String, _ n: Int, _ tint: Color) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(n)")
                .vkFont(.title3, weight: .semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(minWidth: 56, minHeight: DS.Hit.min)
    }

    /// 包3/112 换机恢复后立起验证向导 (与既有 BackupView 同口径; 实体与迁移导入共用 armFirstChecks)
    private func armMigrateWizard(_ n: Int) {
        guard n > 0 else { return }
        BackupStudio.armFirstChecks()
    }
}
