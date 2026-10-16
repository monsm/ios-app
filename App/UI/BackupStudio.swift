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
    @State private var showWebdav = false
    @State private var showMigration = false
    @State private var showFiles = false

    var body: some View { vkBody.destined(.backupStudio) }
    var vkBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    trustHeader
                    actionCards
                    cadenceCard
                    MigrationPromptCard(onOpenMigration: { showMigration = true }).staggered(1)
                }
                .padding(.vertical, DS.Space.m)
            }
            .navigationTitle("备份工作室")
            .variantList()
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
                    Text("数据只存在这台 iPhone")   // 512 数据只存在这台
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
                    Label("AES-128-CBC + HMAC-SHA256 · PBKDF2 60000 轮 — 徽章是「当前代码」用的算法; "   // 37 AES
                          + "每份旧备份自己的参数在「本地备份文件」列表逐文件标注",   // 435 每份旧备份自己的参数
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
            Text("距上次备份已 \(BackupStudio.daysSinceLastExport()) 天")   // 429 距上次备份已
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
            studioRow(title: "导出向导", sub: "分区勾选 · 口令 · 自描述命名 · 二维码搬运",
                      icon: "tray.and.arrow.up", tint: DS.Palette.accentText) { showExport = true }
            studioRow(title: "恢复向导", sub: "预演 · 三策略 · 冲突裁决 · 回滚点",
                      icon: "tray.and.arrow.down", tint: DS.Palette.warn) { showRestore = true }
            studioRow(title: "WebDAV 与策略", sub: "连通测试 · 远端列表 · 节奏三档 · 密钥轮换",   // 197/198/237/422 连通测试
                      icon: "externaldrive.badge.wireless", tint: DS.Palette.accentText) { showWebdav = true }
            studioRow(title: "换机迁移", sub: "三通道向导 · 双机进度 · 差异补传",
                      icon: "iphone.radiowaves.left.and.right", tint: DS.Palette.accentText) { showMigration = true }
            studioRow(title: "本地备份文件", sub: "演练 · 哈希短码 · 双备份对比 · 数据事件",   // 434/436/454/511 演练
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
            // 2026-10-14 材质统一: 通道入口行是坐在页面底上的面板 (它下面就是 gutter)，与同页
            // 三选一卡、预演分段块同材质。这处原本写成两行 `.background(surface,\n in: …)`，
            // 单行正则扫不到 —— 现在信 AST 那条 R6，不信 grep。
            .axGlass(DS.Radius.card)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.gutter)
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
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 713 固定导出目录: 用安全作用域书签记住用户选的文件夹, 之后每次导出都落那里 ——
            // 没设过时回落 App 缓存目录 (系统可能清理), 所以这里把两种落点都写清。
            let _ = dirTick
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("导出目录")   // 713 导出目录
                        .font(.subheadline.weight(.medium))
                    Text(ExportDir.name.isEmpty
                         ? "未设置 — 导出落在 App 缓存目录 (系统可能清理)"
                         : "已固定: \(ExportDir.name)")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
                Spacer(minLength: 0)
                Button(ExportDir.name.isEmpty ? "选择" : "更换") { showDirPicker = true }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                if !ExportDir.name.isEmpty {
                    Button("清除") { ExportDir.clear(); dirTick += 1 }
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                        .frame(minHeight: DS.Hit.min)
                }
            }
            .frame(minHeight: DS.Hit.min)
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
            Toggle("充电时自动备份",   // 428 充电时自动备份
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

// ---------- 445/446 旧机顶部卡: 中断事务 → 退役引导 → 已退役存档 ----------
struct MigrationPromptCard: View {
    @EnvironmentObject var app: AppState
    var onOpenMigration: () -> Void = {}
    @State private var retired: Bool = false
    @State private var firstDone: Bool = false
    @State private var txn: BackupStudio.MigTxn?
    var body: some View {
        Group {
            if let t = txn {
                Card(tint: .warn) {
                    Label("上次换机迁移中断", systemImage: "arrow.uturn.backward")   // 445 上次换机迁移中断
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.warn)
                    Text("临时事务表还在: \(t.channel) 通道已完成 \(t.doneMacs.count) 把锁。回滚 = 回到迁移前; 继续 = 已完成的锁自动跳过。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s) {
                        Button("回滚") {
                            // 2026-10-15 走查: 这颗一键把整库还原到迁移前快照并清掉本轮换机验证记录, 零确认;
                            // 而同一文件里「撤销恢复」那条是走 confirmDestructive 的 —— 两条都是整库级不可逆,
                            // 门槛不该因为按钮在哪一行而不同 (本仓 delsweep 第二张清单讲的就是这种分叉)。
                            confirmDestructive("回滚到迁移前",
                                               "整库恢复到迁移开始前的快照，并清掉本轮的换机验证记录。迁移之后新改动的那些数据会被这份快照盖掉，做完不能撤销。",
                                               confirmTitle: "回滚") {
                                if BackupStudio.rollbackMigrationTxn() {
                                    app.loadDevices()
                                    txn = nil
                                    app.showToast("已回滚到迁移前")   // 445 已回滚到迁移前
                                } else {
                                    app.showToast("回滚失败: 快照不可读")
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.danger)
                        .frame(minHeight: DS.Hit.min)
                        Button("继续") { onOpenMigration() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                }
            } else if retired {
                Card(tint: .warn) {
                    Label("已标记退役", systemImage: "flag.checkered")   // 446 已标记退役
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.warn)
                    Text("建议走 设置→安全中心→销毁 做三级本地销毁; 备份文件是否保留由你决定。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if firstDone {
                Card(tint: .warn) {
                    Label("本机首验清单已全部通过", systemImage: "flag.checkered")   // 446 本机首验清单已全部通
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text("每把锁都已在新机逐把验证过 — 若这台是准备退下的旧机, 标记退役后到 设置→安全中心→销毁 做三级本地销毁。")   // 446 每把锁都已在新机逐把
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("标记退役") {
                        BackupStudio.markRetired()
                        retired = true
                        app.showToast("已标记此设备退役")   // 446 已标记此设备退役
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
        }
        .onAppear {
            txn = BackupStudio.pendingMigrationTxn()
            retired = BackupStudio.retirementBanner
            firstDone = BackupStudio.firstChecksAllDone
        }
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
    @State private var doneURLs: [URL] = []
    @State private var qrPayload: String?
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
                       "门锁钥匙串 + BLE 直连参数")   // 441 门锁钥匙串
            zoneToggle("凭证", counts["凭证"] ?? 0, $zones.credentials,
                       "密码与指纹台账")
            zoneToggle("记录", counts["记录"] ?? 0, $zones.records,
                       // 2026-10-15 走查: 原文案「锁端日志缓存 (按锁约) · N 份缓存」两头都是假的 ——
                       // 锁端日志不进备份包, 这一档裁的是 globals.trace 那一份本机写入轨迹。
                       "本机记录写入轨迹 · 锁端日志缓存根本不进备份包 (要看锁里的记录得到记录页现读)", unit: "份")
            zoneToggle("设置", counts["设置"] ?? 0, $zones.settings,
                       "成员档案 · 应用锁摘要 · dongle/gateway")
            Toggle("包含独立口令组密钥",   // 181 包含独立口令组密钥
                   isOn: $otpToggle)
                .help("勾选后 TOTP 种子/静态码进**备份包体内部**: 随整包口令加密、进校验和、恢复时能读回来。未勾则完全不进包体。仅在勾选\"设置\"分区时生效。")
                .onAppear { otpToggle = BackupStudio.otpIncluded() }
                .onChange(of: otpToggle) { _, on in DB.store.set("kf_bk_otp", on) }
            if useVolumes, let vols = BackupStudio.volumes(zones: zones, encrypt: nil) {
                Text("记录区超阈值, 将拆为 \(vols.count) 卷: 基础卷 + 逐年记录卷, 各卷可独立恢复。")   // 410 记录区超阈值
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    private func zoneToggle(_ title: String, _ n: Int, _ on: Binding<Bool>, _ sub: String, unit: String = "条") -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Toggle(isOn: on) {
                HStack(spacing: DS.Space.s) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    Text("\(n) \(unit)").font(.caption).foregroundStyle(DS.Palette.textSub)
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
        .variantPlate(DS.Palette.surfaceAlt, .tile)
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
            SecureField("再输一遍", text: $pw2)   // 408 再输一遍
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DS.Space.s)
                .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            if !pw.isEmpty && pw != pw2 {
                Text("两次输入不一致")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
            } else if !pw.isEmpty && DB.verifyPasscode(pw) {
                // 549 口令复用检测: 备份口令与应用锁密码相同 → 提示分开设置
                Text("此口令与应用锁密码相同 — 建议两者分开设置。")   // 549 此口令与应用锁密码相
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !pw.isEmpty && (pw.count < 8 || pw.allSatisfy(\.isNumber)) {
                Text("纯数字或过短口令偏弱 — 不拦截, 仅提醒。")   // 408 纯数字或过短口令偏弱
                    .font(.caption)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            // 439 大号百分比 + 分卷序号: 与换机迁移的新机导入页同一对读数, 双机肉眼对齐
            if exporting {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("\(exportPct)%")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(DS.Palette.text)
                        .monospacedDigit()
                    Text(exportVol == 0 ? "组包与加密中…" : "分卷 \(exportVol)/\(exportVolTotal)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ProgressView(value: Double(exportPct), total: 100)
                        .tint(DS.Palette.accentText)
                }
            }
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
            Toggle("先清理过期临时码再导出 (将减少 \(BackupStudio.expiredTemporaryCount()) 条)",
                   isOn: $cleanFirst)
            Toggle("按年分卷", isOn: $useVolumes)   // 410 按年分卷
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
            // 413 完成即分享 (ShareLink 系统面板 + 存储到文件快捷); 410 分卷时每卷各一枚
            ForEach(doneURLs, id: \.self) { url in
                ShareLink(item: url, preview: SharePreview("离线锁管家备份")) {
                    Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                }
            }
            // 411 二维码搬运: 仅凭证小包可生成 QR, 纯本地 CoreImage; 接收端在 换机迁移 的扫码通道
            if let q = qrPayload, let img = BackupStudio.qrImage(q) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("凭证小包二维码搬运: 另一台手机打开 备份工作室→换机迁移→扫码 用相机接收, 全程无网络。")   // 411 凭证小包二维码搬运
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: UIImageShareItem(img), preview: SharePreview("凭证二维码"))
                    Text("口令另行线下交接, 勿与 QR 同渠道 (与导出纪律一致)。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 440 增量补传 (旧机侧): 新机对账报"缺的锁"后, 在旧机只把缺的锁重新打包
            if !DB.keychains().isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("增量补传: 勾选要补的锁, 生成增量小包 (不含记录卷), 传到新机再走一次导入。")   // 440 增量补传
                        .font(.caption)
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
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(DB.ledger(kc.mac).pwds.count + DB.ledger(kc.mac).fps.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            .frame(minHeight: DS.Hit.min)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("生成增量小包 (已勾 \(incSel.count) 把锁)") { makeIncremental() }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(incSel.isEmpty)
                    if let u = incURL {
                        ShareLink(item: u, preview: SharePreview("离线锁管家增量包")) {
                            Text("分享 \(u.lastPathComponent)")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    if !incMsg.isEmpty {
                        Text(incMsg)
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("再生成一份") {
                qrPayload = nil
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
                    qrPayload = BackupStudio.credentialQRPayload()
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
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份", text: $text, axis: .vertical)
                .font(.caption.monospaced())
                .lineLimit(3...6)
                .autocorrectionDisabled()
            SecureField("口令 (带加密的备份才需要)", text: $pw)
                .font(.body)
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
            Text(e)
                .font(.caption)
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
                .font(.subheadline)
                .foregroundStyle(DS.Palette.accentText)
                .fixedSize(horizontal: false, vertical: true)
            // 424 升级链: 逐级列出将要走的步骤 (执行侧 upgradeChain 同顺序同条数)
            let steps = BackupStudio.upgradeSteps(from: p.schema)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Label("旧 schema 自动升级链: v\(p.schema) → v5, \(steps.count) 级", systemImage: "arrow.up.circle")   // 424 自动升级链
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    ForEach(steps) { s in
                        Text("v\(s.from) → v\(s.to): \(s.note)")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // 453 哈希层状态: 解析已过前两层, 这一行的三种状态在预演时就能说清
            switch p.checksum {
            case .ok:
                Label("文件三层检查: 口令层已解 · 文件头已认 · 内容哈希一致", systemImage: "checkmark.seal")   // 453 文件三层检查
                    .font(.caption)
                    .foregroundStyle(DS.Palette.ok)
            case .absent:
                Label("该备份没有校验和字段 (旧包/人工编辑) — 按兼容放行, 内容被改过时无法预警",   // 453 该备份没有校验和字段
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            case .mismatch:
                Label("内容哈希不一致 — 已在解析时拦下", systemImage: "xmark.seal")   // 453 内容哈希不一致
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
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
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("合并策略", selection: $strategy) {   // 418 合并策略
                ForEach(BackupStudio.MergeStrategy.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            Text(strategyHint(strategy))
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 418: 量级预估行 (包内条数 + 同 ID 冲突数), 选策略前先知道规模
            Text("预估: 本包 \(p.pwdCount) 密码/\(p.fpCount) 指纹, 同 ID 冲突 \(conflicts.count) 条")   // 418 预估
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
            // 421 恢复回滚点说明
            Label("执行前自动打本地快照, 24h 内可撤销",   // 421 执行前自动打本地快照
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
            // 456 只读副本浏览: 打开备份内容看一眼, 不写主库 (锁列表 + 随机抽 5 条记录)
            Toggle("以只读副本打开该备份", isOn: $roView)   // 456 以只读副本打开该备份
                .font(.caption)
            if roView, let b = bundle {
                ForEach(b.devices, id: \.mac) { d in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityHidden(true)
                        Text(LockArchive.displayName(d.kc))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\((d.ledger?.pwds.count ?? 0) + (d.ledger?.fps.count ?? 0)) 条凭证 · \(d.meta == nil ? "无运行参数" : "含运行参数")")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            if roView, let lines = p.previewTrace?.prefix(5), !lines.isEmpty {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                    Text(ln)
                        .font(.caption.monospaced())
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: DS.Space.xs) {
                    Text("\(c.kind) #\(c.alias) · \(String(c.mac.prefix(6)))")
                        .font(.caption)
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
        .font(.caption2.weight(.medium))
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
            Label("恢复完成 · 差异报告", systemImage: "checkmark.seal")   // 425 恢复完成
                .font(.headline)
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
                    Text(r.label).font(.subheadline).foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Text("备份 \(r.a) / 本机 \(r.b)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .frame(minHeight: DS.Hit.min)
            }
            // 417 记录时间域: 备份内记录跨度 (trace 行首 16 字符 = yyyy-MM-dd HH:mm), 只读快照
            if let t = preview?.previewTrace, !t.isEmpty {
                Text("记录时间域: \(t.first?.prefix(16) ?? "") ~ \(t.last?.prefix(16) ?? "")")   // 417 界面文案
                    .font(.caption)
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
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("备份 \(d.backup) / 本机 \(d.local) · \(d.note)")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    Text("逐锁对账 (\(b.devices.count) 把)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                }
            }
            // 444 迁移后核对表
            Text("核对表: 对勾 = 该项备份与本机条数一致; 缺的锁可到旧机「导出向导→完成页」用增量补传只勾缺的锁重打小包。")   // 444 核对表
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryActionStyle())
        }
    }
    private func countChip(_ label: String, _ n: Int, _ tint: Color) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(n)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
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
    @State private var hint830 = false          // 830 首次连通成功的一次性加密说明条
    @State private var rotateMsg = ""
    @State private var rotPw = ""
    @State private var busy = false
    @State private var showRotate = false
    @State private var pendingDL: (b: BackupBundle, line: String)?   // 422 预演门: 下载→确认→入库

    private var ready: Bool { !root.isEmpty && !acct.isEmpty && !appPw.isEmpty }

    var body: some View { vkBody.destined(.webDAVStudio) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("WebDAV 端点 (走用户自配账号, 仅 Basic Auth 运行时输入)") {
                    TextField("根地址", text: $root, prompt: Text(BackupStudio.webdavRoot))
                        .autocorrectionDisabled()
                    TextField("账号", text: $acct)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("应用专属密码 (非登录)", text: $appPw)
                    LabeledContent("连通测试") {   // 197 连通测试
                        Button(busy ? "测试中…" : "测试") { test() }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                    if !testResult.isEmpty {
                        Text(testResult).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    // 830 首次连通成功后的"备份将加密后上传"情境条。口径替代记在这: 原句要 3 秒自动收起,
                    // 而本仓有全仓级纪律 (HintOnce.swift:5)「提示不自动计时消失 —— 让它自己飘走,
                    // 等于用户还没读就被判定已看过」; 所以这里由用户点 X 关闭, 只出现一次 (走 HintOnce 记档)。
                    if hint830 {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.ok)
                                .accessibilityHidden(true)
                            Text("备份将加密后上传 · 加密在本机完成, 远端只见密文")   // 830 备份将加密后上传
                                .font(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.Space.xs)
                            Button {
                                withAnimation(DS.Motion.soft) { hint830 = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textSub)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("关闭提示")   // 830 关闭提示
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs)
                        .variantCallout(DS.Palette.ok, .control, wash: 0.12)
                    }
                }
                Section("远端备份 (哈希先行: 先拉 etag 再拉正文)") {
                    if !entries.isEmpty {
                        ForEach(entries) { e in
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(e.name).font(.subheadline).foregroundStyle(DS.Palette.text)
                                HStack(spacing: DS.Space.xs) {
                                    Text("\(e.size / 1024) KB").font(.caption).foregroundStyle(DS.Palette.textSub)
                                    Label(String(e.etag.prefix(8)), systemImage: "number")
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                    // 422 时间列: 服务端 getlastmodified (取不到就空, 不编)
                                    if !e.modified.isEmpty {
                                        Label(BackupStudio.humanDate(e.modified), systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(DS.Palette.textSub)
                                    }
                                }
                                HStack(spacing: DS.Space.s) {
                                    Button("下载恢复") { download(e) }
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .frame(minHeight: DS.Hit.min)
                                    Button("演练") { dryRun(e) }   // 436 演练
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
                    SecureField("新口令 (轮换后旧口令随即失效)", text: $rotPw)
                    Button("密钥轮换: 新口令重加密替换远端") { showRotate = true }   // 237 密钥轮换
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.warn)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(rotPw.isEmpty)
                    if !rotateMsg.isEmpty {
                        Text(rotateMsg).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    Text("口令每次输入不落盘; 轮换后旧口令即失效, 请用新口令访问。")   // 237 口令每次输入不落盘
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("WebDAV 工作室")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                root = DB.store.getString("kf_webdav_root", BackupStudio.webdavRoot)
                acct = DB.store.getString("kf_cloudcfg_acct")
                appPw = DB.store.getString("kf_cloudcfg_app")
            }
            .confirmationDialog("密钥轮换", isPresented: $showRotate) {   // 237 密钥轮换
                Button("轮换") { rotate() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将用新口令重新加密远端备份并替换。旧口令随即失效。")
            }
            // 422 恢复预演门: 下载只做校验与预演, 真正入库要在这里点头
            .confirmationDialog(pendingDL?.line ?? "", isPresented: Binding(
                get: { pendingDL != nil },
                set: { if !$0 { pendingDL = nil } }), titleVisibility: .visible) {
                Button("确认恢复入库") { commitDL() }
                Button("取消", role: .cancel) { pendingDL = nil }
            } message: {
                Text("预演不动真库")   // 422 预演不动真库
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
            // 830 首次连通成功 ⇒ 视为"配置完成": 给一次加密说明情境条 (HintOnce 记档, 之后不再出现)
            if testResult.hasPrefix("连通"), !HintOnce.shown("830enc") {
                HintOnce.mark("830enc")
                withAnimation(DS.Motion.soft) { hint830 = true }
            }
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
                if pruned > 0 { app.showToast("滚动保留: 已清理远端 \(pruned) 份超限") }   // 430 滚动保留
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
                BackupStudio.markExportSize(plain)   // 193: 上传路径也记尺寸
                let env = try CryptoBox.encryptText(plain, password: encPw)
                try await CloudSync.push(acct: acct, app: appPw, envelope: env)
                persist()
                Milestones.recordBackup()
                // 430 上传后自动滚动清理: 最近 N 份之外每月再保最新 1 份 (下载/恢复口不受影响)
                if BackupStudio.rollingKeep > 0 {
                    let n = await BackupStudio.pruneRemote(acct: acct, appPw: appPw, root: root, keep: BackupStudio.rollingKeep)
                    if n > 0 { app.showToast("滚动保留: 已清理远端 \(n) 份超限") }   // 430 滚动保留
                }
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
                guard let url = BackupStudio.safeRemoteURL(root: root, name: e.name) else { throw DFUError.msg("地址非法 (远端条目名被护栏拒绝)") }
                // 423: 清单 etag 先行 — HEAD 比对, 清单过期就中止 (不支持 HEAD 时照常继续, 不假拦)
                var head = URLRequest(url: url); head.httpMethod = "HEAD"
                head.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                if let (_, hr) = try? await URLSession.shared.data(for: head),
                   let h = hr as? HTTPURLResponse, let now = h.value(forHTTPHeaderField: "ETag"),
                   !e.etag.isEmpty, now != e.etag {
                    app.showToast("远端文件已变 (清单 \(e.etag.prefix(8)) ≠ 现在 \(now.prefix(8))), 已中止 — 刷新后重下")   // 423 远端文件已变
                    return
                }
                var req = URLRequest(url: url)
                req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: req)
                let raw = String(data: data, encoding: .utf8) ?? ""
                // 422: 先预演后再入库 (parsePreview 内部先校哈希后解码, 不动真库)
                let (pv, b) = try BackupStudio.parsePreview(text: raw, password: encPw.isEmpty ? nil : encPw)
                pendingDL = (b, e.name + " · 校验通过 · " + pv.zones.joined(separator: "、"))
            } catch { app.showToast(error.localizedDescription) }
        }
    }
    private func commitDL() {
        guard let dl = pendingDL else { return }
        let r = BackupStudio.restore(dl.b, strategy: .merge, zones: BZones())
        if dl.b.globals?.appearance != nil { app.reloadAppearance() }
        app.loadDevices()
        BackupStudio.markImported()
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        pendingDL = nil
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
            app.showToast("需填旧口令(加密口令)与新口令"); return   // 237 需填旧口令
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
/// 438 接收侧的一段备份包: 任意通道 (备份文件/扫码/WebDAV) 收到的原文经 417/453 解析后的产物。
/// 每段带解析时的原始 schema 与哈希层结论 — 预演页据此显示升级链与三层检查。
struct MigSegment: Identifiable {
    let id: String
    let name: String
    let bundle: BackupBundle
    let schema: Int
    let checksum: BackupStudio.ChecksumState
}

struct MigrationWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    // 438 三通道流程: 0 选通道 → 1 通道接收 → 2 预演+441/419 裁决 → 3 真执行(439) → 4 对账+首验(440/442)
    @State private var channel: BackupStudio.Channel = .file
    @State private var step = 0
    @State private var busy = false
    @State private var segments: [MigSegment] = []
    @State private var pw = ""
    @State private var paste = ""
    @State private var layerError: String?
    // 441 逐把确认 (mac → merge/keep/skip): 落 kf_mig_lockact_ 并真进 restore 的 lockActs 入参
    @State private var lockActs: [String: String] = [:]
    // 419 冲突裁决 (id → true 取备份 / false 取本机): 真进 restore 的 conflictTakeBackup
    @State private var conflicts: [BackupStudio.Conflict] = []
    @State private var conflictChoice: [String: Bool] = [:]
    // 439 真进度: 单元 = 设置与成员 + 每把锁, 只随真做完的单元前进
    @State private var doneU = 0
    @State private var totalU = 1
    @State private var runVol = 1
    @State private var runLabel = ""
    @State private var startedAt = Date().timeIntervalSince1970
    // 445 真事务表: 冷启动/进页检测 pendingMigrationTxn — 回滚或续做, 不重画百分比
    @State private var pendingTxn: BackupStudio.MigTxn?
    @State private var resumedFrom = 0
    // 442 首验清单
    @State private var checks: [String] = []
    @State private var checkOn: [String: Bool] = [:]
    // 440 分区对账 + 425 三数 (来自 migrateImport 真实返回值)
    @State private var gaps: [BackupStudio.LockDiff] = []
    @State private var impN = 0
    @State private var ovN = 0
    @State private var skN = 0
    // 各通道的接收态
    @State private var showScan = false
    @State private var showFilePick = false
    @State private var davRoot = ""
    @State private var davAcct = ""
    @State private var davPw = ""
    @State private var davMsg = ""
    @State private var entries: [BackupStudio.RemoteEntry] = []

    var body: some View { vkBody.destined(.migrationWizard) }
    var vkBody: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                Group {
                    if let t = pendingTxn {
                        resumeCard(t)
                    } else {
                        switch step {
                        case 0: channelStep
                        case 1: channelInputStep
                        case 2: previewStep
                        case 3: runningStep
                        default: doneStep
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
            .navigationTitle("换机迁移")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
                    .disabled(busy)
            } }
            .sheet(isPresented: $showScan) {
                MigScanSheet { s in
                    if !s.isEmpty { addSegment(text: s, name: "扫码包") }
                }
            }
            .fileImporter(isPresented: $showFilePick, allowedContentTypes: [UTType.plainText, UTType.data],
                          allowsMultipleSelection: false) { pickedFile($0) }
            .onAppear { loadState() }
        }
    }

    // ---------- 438 三通道向导: 备份文件 / 扫码 / WebDAV (点进各通道自己的接收页) ----------
    private var channelStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("新机首启无数据 — 三选一迁移, 每条通道都有自己的接收页。")   // 438 新机首启无数据
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(BackupStudio.Channel.allCases, id: \.self) { c in
                Button {
                    channel = c
                    layerError = nil
                    withAnimation(DS.Motion.standard) { step = 1 }
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
                    // 2026-10-14 材质统一: 三条恢复通道卡从实底改液态玻璃 (整页主表面同一枚材质)。
                    .axGlass(DS.Radius.card)
                }
                .buttonStyle(.plain)
            }
            Text("三通道都落在同一套 预演→逐把确认→真实入库 上, 一步都不许跳过。")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 438 通道接收页: 每条通道有自己的拿包方式, 统一落成 MigSegment ----------
    private var channelInputStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Label(channel.rawValue, systemImage: channel.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentText)
                    Spacer(minLength: 0)
                    Button("重选通道") {
                        withAnimation(DS.Motion.standard) { step = 0 }
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
                }
                switch channel {
                case .file: fileInput
                case .qr: qrInput
                case .webdav: webdavInput
                }
                SecureField("备份口令 (加密包才需要)", text: $pw)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !segments.isEmpty {
                    segmentList
                }
                if let e = layerError {
                    layerCard(e)
                }
                Button("下一步: 预演与逐把确认") { prepare() }   // 441 下一步
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(segments.isEmpty)
            }
        }
    }
    private var fileInput: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("把旧机导出的 .enc 文本粘贴进来, 或从「文件」App 选一份 (数据线/隔空投送/云盘先落到本机)。分卷时逐卷都加进来。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("粘贴备份文本", text: $paste, axis: .vertical)
                .font(.caption.monospaced())
                .lineLimit(3...6)
                .autocorrectionDisabled()
            HStack(spacing: DS.Space.m) {
                Button("从「文件」选择") { showFilePick = true }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Button("加入粘贴的这一段") { addSegment(text: paste, name: "粘贴段 \(segments.count + 1)") }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private var qrInput: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("旧机在 导出向导 完成页生成凭证二维码; 本机打开相机扫一下, 原文直接进接收队列 — 全程无网络。")   // 411 旧机在
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showScan = true
            } label: {
                Label("打开相机扫码接收", systemImage: "qrcode.viewfinder")   // 411 打开相机扫码接收
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            Text("扫码包只含钥匙串与台账, 不含锁端运行参数与记录; 口令另行线下交接。")   // 411 扫码包只含钥匙串与台
                .font(.caption2)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var webdavInput: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("两台机不见面时走这里: 读远端目录, 列表里选一份接收, 再逐锁入库。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            TextField("根地址", text: $davRoot, prompt: Text(BackupStudio.webdavRoot))
                .autocorrectionDisabled()
            TextField("账号", text: $davAcct)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("应用专属密码 (非登录)", text: $davPw)
            HStack(spacing: DS.Space.m) {
                Button("测试连通") { davTest() }   // 197 测试连通
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                Button("拉取远端列表") { davRefresh() }   // 422 拉取远端列表
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
            }
            ForEach(entries) { e in
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(e.name)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        // 422 时间列: 与上面那份远端列表同口径 (服务端 getlastmodified, 取不到就空, 不编)
                        Text("\(e.size / 1024) KB · etag \(String(e.etag.prefix(8)))"
                             + (e.modified.isEmpty ? "" : " · " + BackupStudio.humanDate(e.modified)))
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                    Button("接收") { davReceive(e) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                }
                .frame(minHeight: DS.Hit.min)
            }
            if !davMsg.isEmpty {
                Text(davMsg)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var segmentList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("已接收 \(segments.count) 段 — 逐段都会进同一次导入")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
            ForEach(segments) { seg in
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: DS.Icon.sm))
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(seg.name)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                        Text(segSummary(seg))
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        segments.removeAll { $0.id == seg.id }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(DS.Palette.textSub)
                            .accessibilityLabel("移除这一段")
                    }
                    .frame(minHeight: DS.Hit.min)
                }
                .frame(minHeight: DS.Hit.min)
            }
        }
    }
    /// 438: 收到的原文先过 417/453 解析 (口令层→文件头层→哈希层), 过了才进接收队列
    private func addSegment(text: String, name: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            let r = try BackupStudio.parsePreview(text: t, password: pw.isEmpty ? nil : pw)
            let id = "\(segments.count)-\(Int(Date().timeIntervalSince1970 * 1000))"
            segments.append(MigSegment(id: id, name: name, bundle: r.bundle,
                                       schema: r.preview.schema, checksum: r.preview.checksum))
            paste = ""
            layerError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            layerError = error.localizedDescription
        }
    }
    private func pickedFile(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let raw = String(data: data, encoding: .utf8) else {
            layerError = "读不到文件内容 — 不是文本备份或没有访问权限"
            return
        }
        addSegment(text: raw, name: url.lastPathComponent)
    }
    private func davTest() {
        Task { davMsg = await BackupStudio.testWebdav(acct: davAcct, appPw: davPw, root: davRoot) }
    }
    private func davRefresh() {
        guard !davRoot.isEmpty, !davAcct.isEmpty, !davPw.isEmpty else {
            davMsg = "先填根地址/账号/应用密码"
            return
        }
        busy = true
        Task {
            do {
                entries = try await BackupStudio.listRemote(acct: davAcct, appPw: davPw, root: davRoot)
                // 2026-10-15 走查: 这里原先在**一次"拉列表"之后**就把 root/账号/应用密码写进全局那三个键 ——
                // 这一屏是换机迁移，用户填的很可能是**旧机那台账号**；点一下「拉取远端列表」就把
                // 备份工作室/设置页配好的端点与口令整组换掉，下一次自动备份就传进另一个账号里去了。
                // 读操作不改全局配置 (本文件顶部那条纪律: "Basic Auth 运行时输入")；要真正常用，
                // 唯一的落盘入口是 WebDAV 那一节的保存 (上面 `DB.store.set` 只在那一处)。
                davMsg = entries.isEmpty ? "远端没有条目 — 先确认旧机已上传" : "共 \(entries.count) 条, 选一份点 接收"
            } catch {
                davMsg = error.localizedDescription
            }
            busy = false
        }
    }
    private func davReceive(_ e: BackupStudio.RemoteEntry) {
        guard let url = BackupStudio.safeRemoteURL(root: davRoot, name: e.name) else {
            layerError = "远端条目名被护栏拒绝"   // 422 远端条目名被护栏拒绝
            return
        }
        busy = true
        Task {
            defer { busy = false }
            var req = URLRequest(url: url)
            req.setValue(CloudSync.basicAuth(davAcct, davPw), forHTTPHeaderField: "Authorization")
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let raw = String(data: data, encoding: .utf8) ?? ""
                if raw.isEmpty {
                    layerError = "远端正文不是 UTF-8 文本"
                } else {
                    addSegment(text: raw, name: e.name)
                }
            } catch {
                layerError = "下载失败: \(error.localizedDescription)"
            }
        }
    }
    /// 进预演前: 跨段去重列冲突 (419)、读回逐把确认 (441), 选择都带进执行
    private func prepare() {
        conflicts = []
        var seen = Set<String>()
        for s in segments {
            for c in BackupStudio.conflicts(s.bundle) where !seen.contains(c.id) {
                seen.insert(c.id)
                conflicts.append(c)
            }
        }
        for c in conflicts where conflictChoice[c.id] == nil { conflictChoice[c.id] = true }
        for k in DB.store.matchingKeys(prefixes: ["kf_mig_lockact_"]) {
            let v = DB.store.getString(k)
            if !v.isEmpty { lockActs[String(k.dropFirst("kf_mig_lockact_".count))] = v }
        }
        layerError = nil
        withAnimation(DS.Motion.standard) { step = 2 }
    }
    private func loadState() {
        pendingTxn = BackupStudio.pendingMigrationTxn()
        if pendingTxn == nil, let s = BackupStudio.pendingMigration(), s.done == false {
            // 445: 事务表不在 = 没有可用快照, 旧会话只描述进度外观 — 清掉, 不给回滚不了的假断点
            BackupStudio.clearMigSession()
        }
        davRoot = DB.store.getString("kf_webdav_root", BackupStudio.webdavRoot)
        davAcct = DB.store.getString("kf_cloudcfg_acct")
        davPw = DB.store.getString("kf_cloudcfg_app")
    }
    /// 441 预演名单: 跨段按规范化 mac 去重, 只列真有 6 字节 mac 与密钥的锁
    private func allLocks() -> [Keychain] {
        var seen = Set<String>()
        var out: [Keychain] = []
        for s in segments {
            for d in s.bundle.devices {
                let mac = DB.normalizeMac(d.mac)
                guard !seen.contains(mac), HexKit.bytes(d.mac).count == 6, !d.kc.skey.isEmpty else { continue }
                seen.insert(mac)
                var kc = d.kc
                kc.mac = mac
                out.append(kc)
            }
        }
        return out
    }
    /// 439: 单元总数与 migrateImport 的口径一致 = 每段 设置与成员 + 每把有效锁
    private func totalUnits() -> Int {
        segments.reduce(0) { acc, s in
            acc + 1 + s.bundle.devices.filter { HexKit.bytes($0.mac).count == 6 && !$0.kc.skey.isEmpty }.count
        }
    }
    private func mergedBundle() -> BackupBundle? {
        guard var out = segments.first?.bundle else { return nil }
        for s in segments.dropFirst() {
            for d in s.bundle.devices where !out.devices.contains(where: { DB.normalizeMac($0.mac) == DB.normalizeMac(d.mac) }) {
                out.devices.append(d)
            }
        }
        return out
    }
    private func segSummary(_ seg: MigSegment) -> String {
        let creds = seg.bundle.devices.reduce(0) { $0 + (($1.ledger?.pwds.count ?? 0) + ($1.ledger?.fps.count ?? 0)) }
        return "锁 \(seg.bundle.devices.count) · 凭证 \(creds) · 成员 \(seg.bundle.members?.count ?? 0) · 包 v\(seg.schema)"
    }

    // ---------- 417/424/453 预演 + 441 逐把确认 + 419 冲突裁决 ----------
    private var previewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("预演: 三层检查已过 — 确认收什么、逐锁怎么迁, 再动库。")   // 417/449 预演
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(segments) { seg in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Label(seg.name, systemImage: "shippingbox")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Text(segSummary(seg))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        checksumLine(seg)
                        let steps = BackupStudio.upgradeSteps(from: seg.schema)
                        ForEach(steps) { s in
                            Text("v\(s.from) → v\(s.to): \(s.note)")   // 424 界面文案
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.m)
                    // 2026-10-14 材质统一: 预演分段块直接坐在页面底上, 属面板级表面 → 玻璃 (tile 档圆角)
                    .axGlass(DS.Radius.tile)
                }
                lockConfirmCard
                if !conflicts.isEmpty {
                    conflictCard
                }
                if resumedFrom > 0 {
                    Label("续迁: 事务表里已有 \(resumedFrom) 把锁, 本次整锁跳过 — 不重做已完成的部分", systemImage: "arrow.uturn.forward")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 421 开始前自动打全库快照
                // 445 开始前自动打全库快照
                Label("开始前自动打全库快照; 中断后回本页可 回滚/继续", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = layerError {
                    layerCard(e)
                }
                BusyButton(title: "开始导入 (\(totalUnits()) 个单元)", systemImage: "tray.and.arrow.down.fill", isBusy: busy) {
                    runImport()
                }
            }
        }
    }
    /// 441: 含多锁时逐把选 合并/保留/跳过 — 选择真进 restore 的 lockActs 入参
    private var lockConfirmCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Label("逐把确认: 合并 = 钥匙串与台账全并; 保留 = 只迁直连参数, 本机台账不动; 跳过 = 整把不动", systemImage: "slider.horizontal.3")   // 441 逐把确认
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(allLocks(), id: \.mac) { kc in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .variantPlate(DS.Palette.surfaceAlt.opacity(0.5), .tile)
    }
    /// 419: 同 ID 冲突逐条裁决 (左本机右备份), 与恢复向导同语义; 默认取备份
    private var conflictCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("\(conflicts.count) 条同 ID 冲突 — 逐条选保留哪边", systemImage: "arrow.triangle.2.circlepath")   // 419 条同
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: DS.Space.xs) {
                    Text("\(c.kind) #\(c.alias) · \(String(c.mac.prefix(6)))")
                        .font(.caption)
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
    /// 419 逐条裁决芯片: 点哪边保留哪边
    private func sideChip(_ id: String, _ backupSide: Bool, _ label: String) -> some View {
        let on = (conflictChoice[id] ?? true) == backupSide
        return Button(label) {
            conflictChoice[id] = backupSide
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.textSub)
        .padding(.horizontal, DS.Space.xs)
        .frame(minHeight: 30)
        .background(on ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt, in: Capsule())
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }
    /// 453 哈希层逐段展示: 解析时已过前两层, 这里只说第三层结论
    @ViewBuilder
    private func checksumLine(_ seg: MigSegment) -> some View {
        switch seg.checksum {
        case .ok:
            Label("三层检查: 口令层已解 · 文件头已认 · 内容哈希一致", systemImage: "checkmark.seal")   // 453 三层检查
                .font(.caption)
                .foregroundStyle(DS.Palette.ok)
        case .absent:
            Label("没有校验和字段 — 兼容放行, 内容被改过时无法预警", systemImage: "exclamationmark.triangle")   // 453 没有校验和字段
                .font(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        case .mismatch:
            Label("内容哈希不一致 — 已在解析时拦下, 到不了这一步", systemImage: "xmark.seal")   // 453 内容哈希不一致
                .font(.caption)
                .foregroundStyle(DS.Palette.danger)
        }
    }

    // ---------- 439 双机并排进度: 大号百分比 + 分卷序号只随真做完的单元走 ----------
    private var runningStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Label(channel.rawValue, systemImage: channel.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                Spacer(minLength: 0)
                Text(segments.count > 1 ? "分卷 \(runVol)/\(segments.count)" : "单元 \(min(doneU + 1, totalU))/\(totalU)")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            ProgressView(value: Double(doneU), total: Double(max(totalU, 1)))
                .tint(DS.Palette.accentText)
            Text("\(runPct)%")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(DS.Palette.text)
                .monospacedDigit()
            Text(runLabel.isEmpty ? "准备中…" : runLabel)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
            Text("旧机导出页与本页同显大号百分比与分卷序号, 双机肉眼对齐; 进度只随真做完的单元前进。")   // 439 旧机导出页与本页同显
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var runPct: Int {
        totalU <= 0 ? 0 : min(100, Int(Double(doneU) / Double(totalU) * 100))
    }

    // ---------- 440 分区对账 + 442 首验清单 + 444 核对 ----------
    private var doneStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Label("导入完成", systemImage: "checkmark.seal")   // 445 导入完成
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ok)
                HStack(spacing: DS.Space.l) {
                    countChip("新增", impN, DS.Palette.ok)
                    countChip("覆盖", ovN, DS.Palette.accentText)
                    countChip("跳过", skN, DS.Palette.warn)
                }
                if gaps.isEmpty {
                    Label("分区对账: 本次接收的锁在新机全部到齐", systemImage: "checkmark.circle.fill")   // 440 分区对账
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.ok)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Label("分区对账: \(gaps.count) 把锁有缺口 — 旧机有新机缺", systemImage: "exclamationmark.circle")   // 440 分区对账
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(gaps) { g in
                            HStack(spacing: DS.Space.s) {
                                Text(g.label)
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("备份 \(g.backup) / 本机 \(g.local) · \(g.note)")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: DS.Hit.min)
                        }
                        Text("补齐方式: 旧机开「备份工作室→导出向导→完成页」, 在增量补传里只勾这些缺的锁生成小包, 回本页用任一通道再接收一次。")   // 440 补齐方式
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("接收补传包 (回通道输入)") {
                            withAnimation(DS.Motion.standard) { step = 1 }
                        }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.m)
                    .variantCallout(DS.Palette.warn, .tile, wash: 0.06)
                }
                Text("核对表: 三数来自本次真实处置; 缺的锁补传后重看这张单。")   // 444 核对表
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                firstChecklist()
                Text("收尾: 首验全部打勾后, 旧机侧备份页会亮出 标记退役 引导, 再做三级本地销毁收尾。")   // 446 收尾
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    // ---------- 442 首验清单: 逐项打勾, 与设备页逐锁验证 (kf_migok_) 同口径 ----------
    private func firstChecklist() -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("首验清单: 在新机真机上逐项验证后打勾", systemImage: "checklist")   // 442 首验清单
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(checks, id: \.self) { k in
                HStack(spacing: DS.Space.s) {
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
                    // 2026-10-15 走查: 原先只有"勾上"才落盘, 取消勾选只改本地 @State —— 而这四格的
                    // 初值读的就是盘上那份, 于是取消会在下次进场被悄悄改回来。勾与不勾都写, 屏上与台账
                    // 才是同一个量 (armFirstChecks 现在会在新一轮迁移开始时把这份整体清掉)。
                    BackupStudio.markFirstCheck(k, on: checkOn[k] == true)
                    if checkOn[k] == true {
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
    private func countChip(_ label: String, _ n: Int, _ tint: Color) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(n)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(minWidth: 56, minHeight: DS.Hit.min)
    }
    // 441 逐锁动作: mac → merge/keep/skip, 落 kf_mig_lockact_ 并在预演时读回
    private enum LockAction: String { case merge, keep, skip }
    private func lockActionChip(_ mac: String, _ a: LockAction, _ label: String) -> some View {
        let on = (lockActs[mac] ?? "merge") == a.rawValue
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
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    // ---------- 445 中断续迁: 事务表还在 → 回滚 / 继续 (已落库的锁不重做) ----------
    private func resumeCard(_ t: BackupStudio.MigTxn) -> some View {
        Card(tint: .warn) {
            Label("上次换机迁移中断", systemImage: "arrow.uturn.backward")   // 445 上次换机迁移中断
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.warn)
            Text("临时事务表还在: \(t.channel) 通道已落下 \(t.doneMacs.count) 把锁。回滚 = 整库回到迁移前; 继续 = 重新接收备份, 已落库的锁自动整锁跳过。")   // 421 临时事务表还在
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s) {
                Button("回滚") {
                    // 2026-10-15 走查: 与上面那枚「回滚」同一件事、同样零确认 —— 上面那张卡已经把后果
                    // 写在文案里, 但"写在旁边"和"按下去再问一次"是两件事, 整库级还原两条都该问。
                    confirmDestructive("回滚到迁移前",
                                       "整库恢复到迁移开始前的快照，已落库的 \(t.doneMacs.count) 把锁与之后改动的数据都会被这份快照盖掉，并清掉本轮换机验证记录。做完不能撤销。",
                                       confirmTitle: "回滚") {
                        if BackupStudio.rollbackMigrationTxn() {
                            pendingTxn = nil
                            resumedFrom = 0
                            app.loadDevices()
                            app.showToast("已回滚到迁移前")   // 445 已回滚到迁移前
                        } else {
                            app.showToast("回滚失败: 快照不可读")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(DS.Palette.danger)
                .frame(minHeight: DS.Hit.min)
                Button("继续迁移") {
                    channel = BackupStudio.Channel(rawValue: t.channel) ?? .file
                    resumedFrom = t.doneMacs.count
                    pendingTxn = nil
                    withAnimation(DS.Motion.standard) { step = 1 }
                }
                .font(.subheadline)
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
            }
        }
    }

    // ---------- 439/441/445 真执行: 事务表开局 + 逐段逐锁真实入库 ----------
    private func runImport() {
        guard !segments.isEmpty else { return }
        busy = true
        layerError = nil
        impN = 0
        ovN = 0
        skN = 0
        doneU = 0
        runVol = 1
        runLabel = ""
        totalU = totalUnits()
        startedAt = Date().timeIntervalSince1970
        // 419: 卡片上逐条选定的保留方 (默认取备份) 真送进 restore 入参
        var take = Set<String>()
        for c in conflicts where (conflictChoice[c.id] ?? true) { take.insert(c.id) }
        let acts = lockActs
        let segs = segments
        Task {
            // 445: 先立/沿用事务表 — 打不出迁移前快照就不开跑
            guard BackupStudio.beginMigrationTxn(channel: channel.rawValue) else {
                busy = false
                layerError = "打不出迁移前全库快照 — 没有回滚点就不开跑"   // 445 打不出迁移前全库快照
                return
            }
            saveSession(false)
            var offset = 0
            for (i, seg) in segs.enumerated() {
                runVol = i + 1
                // 445: 每段调用前重读事务表 — 本段/上一段已落库的锁整锁跳过, 不重做
                let skip = Set(BackupStudio.loadMigTxn()?.doneMacs ?? [])
                let r = await BackupStudio.migrateImport(seg.bundle, zones: BZones(),
                                                         lockActs: acts,
                                                         conflictTakeBackup: take,
                                                         skipMacs: skip) { done, _, name in
                    doneU = offset + done
                    runLabel = name
                }
                offset += 1 + seg.bundle.devices.filter { HexKit.bytes($0.mac).count == 6 && !$0.kc.skey.isEmpty }.count
                impN += r.imported
                ovN += r.overwritten
                skN += r.skipped
                saveSession(false)
            }
            // 445 结算: 事务清掉 = 本轮闭环; 442 立起首验 (设备页连上每把锁时写 kf_migok_)
            BackupStudio.finishMigrationTxn()
            BackupStudio.armFirstChecks()
            doneU = totalU
            runLabel = "全部单元完成"
            gaps = mergedBundle().map { BackupStudio.lockGaps($0) } ?? []
            checks = ["开一次门", "看一条记录", "验一处遮蔽状态", "每把锁直连重激活"]   // 443 每把锁直连重激活
            checkOn = BackupStudio.firstChecks()
            app.loadDevices()
            saveSession(true)
            busy = false
            withAnimation(DS.Motion.standard) { step = 4 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.showToast("换机迁移完成")
        }
    }
    private func saveSession(_ done: Bool) {
        BackupStudio.saveMigSession(BackupStudio.MigSession(
            channel: channel.rawValue, startedAt: startedAt,
            step: doneU, total: max(totalU, 1), imported: impN + ovN, done: done))
    }
    private func finish() {
        BackupStudio.recordEvent("换机迁移")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
    private func layerCard(_ e: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Label("解析/执行未通过", systemImage: "exclamationmark.triangle")   // 453 解析
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
            Text(e)
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .variantCallout(DS.Palette.warn, .tile, wash: 0.06)
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
        case .file: return "旧机导出 .enc 后经数据线/隔空投送/云盘传到本机, 这里粘贴或从「文件」选择接收"   // 438 旧机导出
        case .qr: return "仅凭证小包: 旧机导出页生成二维码, 本页相机扫码接收, 全程无网络"   // 411/438 仅凭证小包
        case .webdav: return "坚果云/自配 WebDAV: 读远端列表 → 下载 → 解析入库, 两台机不见面也能迁"   // 422/423 坚果云
        }
    }
}

/// 411 扫码接收端 (新机侧): 扫旧机 导出向导 完成页的凭证二维码 → 原文交给换机迁移接收队列。
/// ⚠ CredentialStudio.swift 里 DataScannerView 的调用形状禁止改写 — 它已挂在 docs/API-VERIFY.md:
/// 「撞不到 Apple 文档、形状高度可疑、在编译器看过之前不许凭记忆重写」。本页只接接收侧流程
/// (拿到原文 → 上层 417/453 解密解析入库), 调用形态逐字复用 522 的那一处, 不做任何猜改。
struct MigScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (String) -> Void
    @State private var fired = false

    var body: some View {
        NavigationStack {
            DataScannerView { results in
                for r in results {
                    if let s = r.codeString {
                        guard fired == false else { return }
                        fired = true
                        onResult(s)
                        dismiss()
                        return
                    }
                }
            }
            .navigationTitle("扫码接收")   // 411 扫码接收
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            } }
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
    // 432 每行概览: 体积/时间来自文件属性, 内容概览要能解密才算得出, 密文包如实标"需口令"
    @State private var cover: [String: String] = [:]
    // 433 别名/备注: **只改显示**, 文件名与内容不动 (哈希短码 434 仍指向同一个文件)
    @State private var aliases: [String: String] = DB.store.get([String: String].self, "kf_bk_note") ?? [:]
    @State private var editingFile = ""
    @State private var showEditAlert = false
    @State private var noteDraft = ""
    // 437 复核钉: 键一律是真实文件名 (别名可能被人改), 到期天数在进页时算一次
    @State private var pins: [String: String] = BackupStudio.pins()
    // 435 逐文件算法标注: 读文件头即可 (不解密), 也在进页时算一次, 不放 body 里重复读盘
    @State private var algos: [String: BackupStudio.AlgoNote] = [:]
    @State private var pinOver: [String: Int] = [:]
    @State private var pinFile = ""
    @State private var pinDay = Date()
    @State private var showPinSheet = false

    /// 重读复核钉 (钉完/撤完/回本页时都按当前磁盘与日历重算一遍到期)
    private func reloadPins() {
        pins = BackupStudio.pins()
        pinOver = Dictionary(uniqueKeysWithValues: BackupStudio.duePins().map { ($0.file, $0.overDays) })
    }

    /// 433: 备注可能两行 (别名 + 一句话说明), 第一行当显示名
    private func aliasOf(_ u: URL) -> String {
        (aliases[u.lastPathComponent] ?? "").split(separator: "\n").first.map(String.init) ?? ""
    }

    /// 433/437/404 每行的长按菜单 —— 2026-10-13 run 63 从 body 内联的 .contextMenu 块抽出:
    /// 内联时整个列表行表达式报 "unable to type-check this expression in reasonable time"。
    @ViewBuilder
    private func fileContextMenu(_ u: URL) -> some View {
        Button("加备注 / 改名显示") {   // 433 加备注
            editingFile = u.lastPathComponent
            noteDraft = aliases[u.lastPathComponent] ?? ""
            showEditAlert = true
        }
        Button("设复核日期") {   // 437 设复核日期
            pinFile = u.lastPathComponent
            pinDay = BackupStudio.dayDate(pins[pinFile] ?? "") ?? Date()
            showPinSheet = true
        }
        if aliases[u.lastPathComponent] != nil {
            Button("去掉备注", role: .destructive) {
                var m = aliases
                m.removeValue(forKey: u.lastPathComponent)
                aliases = m
                DB.store.setCodable("kf_bk_note", m)
            }
        }
        if pins[u.lastPathComponent] != nil {
            Button("撤掉复核钉", role: .destructive) {
                BackupStudio.setPin(u.lastPathComponent, "")
                reloadPins()
            }
        }
        // 404: 到期备份的手动删除出口 (此前这一族没有删除动作, 提示"手动删除"没有落点)。
        // 删除面只对本列表里真实存在的这一份文件, 且必须走 confirmDestructive 二次确认。
        Button("删除这份备份", role: .destructive) {   // 404 删除这份备份
            confirmDestructive("删除这份备份?",
                               "将删除本机上的 \(u.lastPathComponent) — 不可恢复; 其它设备或远端上的副本不受影响。",
                               confirmTitle: "删除") {
                try? FileManager.default.removeItem(at: u)
                files.removeAll { $0 == u }
                sel.remove(u)
            }
        }
    }

    private func sizeOf(_ u: URL) -> String {
        let b = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return DataHealth.human(b)
    }
    private func mtimeOf(_ u: URL) -> String {
        guard let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return "?" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
    /// 432 的"记录起止覆盖列"**做不到**：本机备份包 (BackupBundle) 只有 devices/ledger/members/globals，
    /// 不含任何记录日志 —— 拿"覆盖的起止日期"就是编。这里改成包体里真有的东西：备份时刻、几台锁、几条凭证。
    /// 密文包不猜内容，如实标"需口令"。
    private func buildCover(_ list: [URL]) {
        var m: [String: String] = [:]
        for u in list.prefix(40) {
            guard let b = try? decodeBundle(u) else { m[u.lastPathComponent] = "需口令"; continue }
            let cred = b.devices.reduce(0) { $0 + (($1.ledger?.pwds.count ?? 0) + ($1.ledger?.fps.count ?? 0)) }
            m[u.lastPathComponent] = "备份于 \(b.at.prefix(16)) · \(b.devices.count) 台锁 · \(cred) 条凭证"
        }
        cover = m
    }
    /// 434/435/437/404 本地备份的一份文件行 —— 2026-10-13 run 63 从 body 的 ForEach 里抽出:
    /// 整个行表达式报 type-check 超时。
    @ViewBuilder
    private func fileRow(_ u: URL) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack {
                // 433: 有备注就显示备注, 文件名退到下一行小字 (文件名本身不动)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(aliasOf(u).isEmpty ? u.lastPathComponent : aliasOf(u))
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !aliasOf(u).isEmpty {
                        Text(u.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                // 2026-10-13 run 65: `sel.toggle(u)` —— Set 没有 toggle(_:) (报 "has no dynamic member
                // 'toggle'"); 显式写 contains/insert/remove。
                Button(u.lastPathComponent) {
                    if sel.contains(u) { sel.remove(u) } else { sel.insert(u) }
                }
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
                // 432 体积与文件时间 (文件属性, 不用解密, 永远说得出口)
                Text("\(sizeOf(u)) · \(mtimeOf(u))")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            // 435: 这一份自己的算法参数 (从信封读出来, 不是工作室那枚"当前代码用什么"的徽章)
            if let n = algos[u.lastPathComponent] {
                Group {
                    switch n {
                    case .envelope(let s): Text("\(s)")   // 435 界面文案
                    case .plain: Text("明文包 · 没有加密信封")   // 435 明文包
                    case .unknown: Text("未能从文件头识别算法")   // 435 未能从文件头识别算法
                    }
                }
                .font(.caption2)
                .foregroundStyle(n == .unknown ? DS.Palette.warn : DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            }
            // 432: 内容概览 (备份包不含记录, 所以这里只有台账/成员规模, 密文标"需口令")
            if let c = cover[u.lastPathComponent] {
                Text(c)
                    .font(.caption2)
                    .foregroundStyle(c == "需口令" ? DS.Palette.warn : DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 437: 复核钉状态 (未到日只是小字存档, 到日才变橙)
            if let day = pins[u.lastPathComponent] {
                if let n = pinOver[u.lastPathComponent] {
                    Text("复核钉 \(BackupStudio.pinDayText(day)) · 今天该复核 (已过 \(n) 天)")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    // 404: 到日这一份提示手动销毁/删除 —— 删除出口在本行长按菜单里 (带二次确认)
                    Text("已到复核日: 核对后手动删除这份备份, 或重做一份新的再删旧的")   // 404 已到复核日
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("复核钉 \(BackupStudio.pinDayText(day)) · 未到日不催")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
        }
        .contextMenu { fileContextMenu(u) }
        // 404 到期行置灰: 复核钉到日 (pinOver 有值) 的这一份压暗, 与上面那句提示同一判据
        .opacity(pinOver[u.lastPathComponent] != nil ? 0.55 : 1)
    }


    var body: some View { vkBody.destined(.localFiles) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section("本地备份 (哈希短码 / 演练 / 双备份对比)") {
                    if files.isEmpty {
                        Text("暂无本地备份 — 先到导出向导生成")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(files, id: \.self) { u in
                        fileRow(u)
                    }
                    if sel.count == 2, let a = sel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
                       let b = sel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last {
                        Button("对比两份") {   // 454 对比两份
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
                        Section("对比结果") {   // 454 对比结果
                            ForEach(rows) { r in
                                HStack(spacing: DS.Space.s) {
                                    Text(r.label).font(.subheadline).foregroundStyle(DS.Palette.text)
                                    Spacer(minLength: 0)
                                    Text("甲 \(r.a) / 乙 \(r.b)").font(.caption).foregroundStyle(DS.Palette.textSub)
                                }
                            }
                        }
                    }
                    SecureField("口令 (演练/对比加密件需要)", text: $pw)
                    Button("对选中文件演练恢复") { dryRunSel() }   // 436 对选中文件演练恢复
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.warn)
                    if !dryRun.isEmpty {
                        Text(dryRun).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                }
                Section("管家交接包: 备份 + 使用说明合并导出, 换管理员一键交接") {   // 1048 管家交接包
                    Button {
                        if pw.isEmpty {
                            app.showToast("请先在上方填写交接口令 — 交接包含门锁密钥, 必须加密")
                        } else if let h = BackupStudio.handoverPackage(password: pw) {
                            UIPasteboard.general.string = h.text
                            let url = BackupStudio.dir.appendingPathComponent(h.fileName)
                            // 2026-10-14: 写盘失败仍回执"已写入本机"是假回执; 剪贴板有数据但本地文件没有。
                            if (try? h.text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                                app.flashReceipt("已写入本机")   // 508 已写入本机
                            }
                            app.showToast("交接包已加密并复制到剪贴板, 口令请另行线下交接")   // 1048 交接包已生成并复制到
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
                Section("数据事件: 本机记的导出 / 恢复 / 迁移 三类节点") {   // 511 数据事件
                    ForEach(BackupStudio.dataEvents(), id: \.self) { s in
                        Text(s).font(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("本地备份文件")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                // 2026-10-13 run 65: 原来把 `(try? contentsOfDirectory(...))?.filter{…}?.sorted{…} ?? []`
                // 写成一条链, 报 "cannot use optional chaining on non-optional value of type '[URL]'"。
                // 拆开: 先 ?? [] 收成非可选, 再 filter/sorted。
                let found = (try? FileManager.default.contentsOfDirectory(
                    at: BackupStudio.dir, includingPropertiesForKeys: nil)) ?? []
                files = found
                    .filter { $0.lastPathComponent.hasSuffix(".enc") }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                buildCover(files)   // 432: 概览要解密, 只在进页时算一次, 不放 body 里 (每帧重解会卡)
                // 435: 只读每个文件的头 4KB, 不解密; 认不出信封的走"未能识别", 不套徽章那串
                algos = Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, BackupStudio.algoNote($0)) })
                reloadPins()        // 437: 到期与否跟日历走, 每次进页重算
            }
            // 433: 备注/别名只存本机显示用 (kf_bk_note), 文件名与内容都不动
            .alert("备注 / 改显示名", isPresented: $showEditAlert) {   // 433 备注
                TextField("如: 换机前 final", text: $noteDraft)
                Button("保存") {
                    var m = aliases
                    let t = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { m.removeValue(forKey: editingFile) } else { m[editingFile] = t }
                    aliases = m
                    DB.store.setCodable("kf_bk_note", m)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只改这一页的显示, 文件名、内容与哈希都不变；备份列表仍按文件名排序。")   // 433 只改这一页的显示
            }
            // 437 复核钉设置页: 钉的是"哪天该复核这份备份", 到日才在设备页催 (未到日只在小字里存档)
            .sheet(isPresented: $showPinSheet) {
                NavigationStack {
                    Form {
                        DatePicker("复核日期", selection: $pinDay, displayedComponents: .date)
                        Text("目标: \(pinFile)\n到日之后设备页 Hero 卡下会催一行, 点「知道了」停止催这一钉；把日期挪到新一天会重新催。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("存这个复核日") {
                            let day = BackupStudio.dayString(pinDay)
                            BackupStudio.setPin(pinFile, day)
                            reloadPins()
                            showPinSheet = false
                            app.showToast("已钉 \(BackupStudio.pinDayText(day)) 复核 \(BackupStudio.pinLabel(pinFile))")   // 437 已钉
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                    }
                    .navigationTitle("备份复核钉")   // 437 备份复核钉
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { Button("取消") { showPinSheet = false } }
                    }
                }
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
            throw DFUError.msg("不是有效备份 (魔数/文件头层)")
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
            if BackupStudio.verifyChecksum(body) {
                // 436: 抽样数实算 (parsePreview 真抽一遍), 不再写死 "5 条"
                let sampled = (try? BackupStudio.parsePreview(text: body, password: nil).preview.sampleOk) ?? 0
                dryRun = "已验证 · 抽样 \(sampled) 条可解析 · 哈希 " + BackupStudio.shortHash(body)
            } else {
                dryRun = "哈希不一致 — 该份备份可能损坏, 建议重下"   // 423 哈希不一致
            }
        } catch {
            dryRun = error.localizedDescription
        }
    }
}
