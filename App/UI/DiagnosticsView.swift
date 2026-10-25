// 运行日志/诊断 — 汇总运行状态与日志, 一键复制发给开发者排障
import SwiftUI
import UIKit
import Charts

struct DiagnosticsView: View {
    @EnvironmentObject var app: AppState
    // 2026-10-15 走查: 这一页有三条来路 —— 设备页 push、设置页 push、以及设置页那张 sheet
    // (`SettingsView` 的 `showDiag` = `NavigationStack { DiagnosticsView() }`)。
    // 空态那枚「去设备页操作」原先只写 `app.tabSelection = 0`：sheet 那条路里 TabView 整个被盖住
    // ⇒ 点了没反应，甩掉 sheet 才发现自己在设备页 (§7.3 那一族)。
    @Environment(\.dismiss) private var dismiss
    @State private var debugRaw = DB.store.getBool("kf_debug_raw")
    @State private var copied = false
    @State private var dumpedLine: LogLine?   // 740 原始报文 hex dump 的当前行
    @State private var results: [HealthCheckItem] = []   // 149 体检结果
    @State private var score = 0
    @State private var integrityReport: [String] = []    // 750 完整性自查输出
    // 397 的结果不放本页 @State: 解锁时跑的那一次存在 AppState, 手动按钮也写同一处, 避免两份状态各说各话
    @State private var logLevelFilter = ""               // 153 级别过滤: "" / info / warn / error
    @State private var pageTraceOn = PageTrace.isOn      // 280 采集开关 (默认关)
    @State private var logQuery = ""                     // 154 关键词高亮
    // 542 时间窗刷选: 拖动选中的小时段 (nil = 不筛); winDragging 区分"按下起点"与"拖到终点"
    @State private var winFrom: Int? = nil
    @State private var winTo: Int? = nil
    @State private var winDragging = false
    // 239 诊断截图: 渲染好的一张带时间水印的图 (nil = 还没生成)
    @State private var diagShot: UIImage?
    @State private var entityRef: DiagLogs.EntityRef?    // 543 实体跳转: 当前点中的引用
    @State private var retentionAsk: (String, Int)? = nil   // 751: (待应用的新档值, 将删条数) — 二次确认用

    /// 752 清理前提醒: 7 天内没有本机备份就先二次确认 (沿用 DestroyKit 的同一备份闸口径), 有备份则直接执行。
    private func guardOrBackup(_ work: @escaping () -> Void) {
        guard !DestroyKit.backupGatePass else { work(); return }
        let alert = UIAlertController(title: "最近 7 天没有备份",
                                      message: "清理或归档会改动本地数据。建议先导出备份再执行；也可以继续当前操作。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "仍要执行", style: .destructive) { _ in work() })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 814 空态进度点: 三格依次是「有一把真锁 → 跑过一次一键体检 → 这里出现记录」。
    /// 前两格数的是真实状态 (设备表 / 体检存档)，第三格在这个空态分支里必然没做到 ——
    /// 圆点亮的就是"还差哪一步"，不是装饰。此前唯一一处 GuidedEmptyView 调用没传 step，814 从未渲染过。
    private var logGuideStep: Int {
        (app.devices.isEmpty ? 0 : 1) + (DiagHealth.archives().isEmpty ? 0 : 1)
    }

    private func rerunAll() {
        let r = DiagHealth.runAll()
        score = r.score
        results = r.items
        DS.Haptics.tick.impactOccurred()
    }
    private func retest(_ id: String) {
        guard let fresh = DiagHealth.runItem(id) else { return }
        if let i = results.firstIndex(where: { $0.id == id }) { results[i] = fresh }
        // 总分随单项变化重算, 免得出现"全绿但总分还是旧值"的自相矛盾;
        // 口径走 DiagHealth.percent 单一出口 (与 runAll 同源), 不在视图里另写一套算术
        score = DiagHealth.percent(results)
        app.showToast("\(fresh.name): \(fresh.ok ? "通过" : "待处理")")
    }
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    // ---------- 749 待补拉日期段: 展示行 (制式与本页 451/体检分项一致: 图标 + 主行 + 判据小字) ----------
    /// 749 封面行文案: 三种"没有可推断的数据"各说各话, 不给一个含糊的"无"
    private func pullCoverLine(_ r: PullGapReport) -> String {
        if r.noLogs { return "本机还没有这把锁的日志" }
        if let f = r.firstDay { return "本机 \(f) ~ \(r.lastDay ?? f) · 覆盖 \(r.coveredDays) 天" }
        return "本机 \(r.totalRows) 行都没有有效锁端时刻"
    }
    /// 749 一段日期 (中段空洞与尾段共用这一行形状; tag 把"尾段"和空洞分开念)
    @ViewBuilder
    private func pullGapRow(_ s: PullSegment, tag: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.sm))
                .foregroundStyle(DS.Palette.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(tag + s.line)
                    .vkFont(.subheadline, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.basis)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        // 749 无障碍触达: 与本页 366 任务行同一个 minHeight 制式
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
    }
    /// 749 序号断档行 (信号 B; 每行只给号数, 判据集中写在下面那一行, 免得五行重复同一句话)
    @ViewBuilder
    private func idxGapRow(_ g: IdxGap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: "list.number")
                .font(.system(size: DS.Icon.sm))
                .foregroundStyle(DS.Palette.textSub)
                .accessibilityHidden(true)
            Text(g.line)
                .vkFont(.subheadline)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.text)
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
    }

    var body: some View { vkBody.destined(.diagnostics) }
    var vkBody: some View {
        Form {
            // 366 月度清理任务: 每月 1 日在页顶出一条任务行; 过期口径与 431 清理同源 (expiredTemporaryCount),
            // 点按走通知落地同一条路 —— 切凭证 Tab 并开整理面板 (pendingCredPanel 词表内的 organize)。
            let monthlyExpired = BackupStudio.expiredTemporaryCount()
            if WeekCal.gregorian.component(.day, from: Date()) == 1, monthlyExpired > 0 {
                Section("月度清理") {   // 366 月度清理
                    Button {
                        // 2026-10-14 走查: 本页不止从设置页进 —— 设备页「打开排查工具」也推它
                        // (DeviceHomeView 的 failStreak≥3 卡), 而设备页在访客通道下照常可达。
                        // 直写 tabSelection=1 会落到一个不进层级树的 Tab, 走 requestTab 才过 377 门禁。
                        app.requestRoute(.credentials)
                        app.pendingCredPanel = "organize"
                        // 2026-10-15 走查: requestTab 管的是**访客门禁**，管不到"这一层盖在 TabView 上"——
                        // 本页从设置页是以 sheet 进来的 (`showDiag`)，不收掉这层，切过去的凭证 Tab 就在 sheet 底下 (§7.3 那一族)。
                        // 与 `CredentialStudio` 三枚「查看」的形状一致（那边有 embedded，所以写 `if !embedded { dismiss() }`；
                        // 本页三条来路——设备页 push、设置页 push、设置页 sheet——**都该退一层**，所以不收在条件里）。
                        dismiss()
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(DS.Palette.warn)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("过期凭证 \(monthlyExpired) 条待处理")   // 366 过期凭证
                                    .vkFont(.subheadline, weight: .medium)
                                    .foregroundStyle(DS.Palette.text)
                                Text("每月 1 日提醒 · 点按进凭证页整理面板")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            }
            Section("诊断报告") {
                Button {
                    UIPasteboard.general.string = report()
                    copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Label(copied ? "已复制, 请粘贴发给开发者" : "复制全部诊断信息",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                // 状态不只靠颜色: 图标在 checkmark.circle / doc.on.doc 之间切换, 且播报给 VoiceOver
                .foregroundStyle(copied ? DS.Palette.ok : DS.Palette.accentText)
                .accessibilityLabel(copied ? "已复制, 请粘贴发给开发者" : "复制全部诊断信息")
                .accessibilityValue(copied ? "已复制到剪贴板" : "")
                Text("报告包含: 一行留白的问题描述、应用/系统版本、全部已配对锁的清单、本次体检分项、最近 100 条会话日志与近 7 天留档日志。回到对话窗口直接粘贴即可 —— 这里没有表单, 也不会替你提交什么。")   // 299 报告包含
                    .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 157 诊断包分享: 与"复制"同一份 report(), 走系统分享面板 (不落盘、不上传)。
                // 口径降级写在这里也写在报告头部: 原案是 zip 包, 本工程给的是**一份纯文本分节**，不假装打了包。
                ShareLink(item: report()) {
                    Label("分享诊断报告", systemImage: "square.and.arrow.up")   // 157 分享诊断报告
                }
                .vkFont(.footnote)
                // 239 导出截图 (带时间水印): 报告本身是纯文本、没有截图可叠水印 —— 所以这里**渲染**一张:
                // ImageRenderer 把报告画成图, 再叠一条"离线锁管家 · 时间"的对角水印,
                // 防的是"转发出去没人知道是哪台机、什么时候导的"。渲染不出就退回上面那条文本分享, 不静默失败。
                if let shot = diagShot {
                    // 预览用纯标题形状: SharePreview(_:image:) 在这版 SDK 上编译不过 ("extraneous argument label 'image:'"),
                    // 而 SharePreview(_:) 是稳的 —— 分享面板仍有标题, 只是没有渐变封面。
                    ShareLink(item: UIImageShareItem(shot),
                              preview: SharePreview("诊断截图")) {   // 239 诊断截图
                        Label("分享诊断截图", systemImage: "photo.on.rectangle.angled")   // 239 分享诊断截图
                    }
                    .vkFont(.footnote)
                    Button("重新生成截图") { diagShot = renderDiagShot() }
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(minHeight: DS.Hit.min)
                } else {
                    Button("生成诊断截图") { diagShot = renderDiagShot() }   // 239 生成诊断截图
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                    Text("截图 = 整份报告 + 对角时间水印; 转发出去一眼能看出是哪台机、什么时候导的。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 包11 查阅表: 错误码/型号/字段/图标语义/二维码/崩溃档案, 全部只读
                NavigationLink { DiagReferenceView().environmentObject(app) } label: {
                    Label("诊断查阅", systemImage: "text.book.closed")   // 159/661/662/753/754/758 诊断查阅
                }
                .vkFont(.footnote)
            }
            // 149/150/160/158/151 一键体检: 引擎 (DiagHealth) 一直在, 此前**全库没有任何界面调用它** →
            // 现在跑分、单项复测、结果存档、权限深链四件事一次接上。
            Section("一键体检") {   // 149/160 一键体检
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text("总分 \(score) / 100")
                        .vkFont(.title3, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.text)
                    Spacer()
                    Button("全部重跑") { rerunAll() }
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                }
                .accessibilityElement(children: .combine)
                ForEach(results) { it in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: it.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(it.ok ? DS.Palette.ok : DS.Palette.warn)
                                .accessibilityHidden(true)
                            Text(it.name)
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: DS.Space.s)
                            Button("重测 (\(it.id))") { retest(it.id) }   // 160 单项复测
                                .vkFont(.caption, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                        }
                        Text(it.detail)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 151 权限自查: 只有**系统权限类**且未通过时才给入口。
                        // 能给的只有"本 App 的设置页" (UIApplication.openSettingsURLString 是唯一公开出口),
                        // iOS 不提供给"蓝牙/通知"单项的深链 —— 声称能直接跳到那一项就是假功能。
                        if ["ble", "notify"].contains(it.id) && !it.ok {
                            Button("打开系统设置中的本 App 权限页") { openAppSettings() }
                                .vkFont(.caption, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                            Text("系统只能打开本 App 的设置页，进去后手动找「\(it.name)」")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 151 面容 ID: 录入动作在**系统设置**里, 本 App 设置页没有这一项 —— 不给按钮
                        // (按下去帮不上忙), 只给如实步骤; 检测口径 = DiagKit 545 项 (AuthKit.biometricAvailable)
                        if it.id == "faceid" && !it.ok {
                            Text("想让面容可用: 到 系统设置 ‹ 面容 ID 与密码 录入面容后回来「重测」。iOS 没有直达该页的公开深链，本 App 设置页里也没有这一项；本机无生物识别硬件时可忽略此行 (该能力走 DEFERRED)。")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                // 151 本地网络: iOS 没有"本地网络授权"的公开查询 API; 本 App 与门锁走蓝牙直连, 全仓无
                // 局域网通信也未申请该权限 —— 如实说明, 不摆一个永远绿的检查项 (那才是假检查)
                Text("本地网络: 本 App 不申请也不使用 —— 与门锁走蓝牙直连，无局域网通信；系统设置里查不到本 App 的本地网络记录是正常的。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s) {
                    Button("存档本次结果") {   // 158 存档本次结果
                        DiagHealth.saveArchive((score: score, items: results))
                        app.showToast("已存档 \(DiagHealth.archives().count) 份历史记录")
                    }
                    .vkFont(.footnote)
                    Spacer()
                    if !DiagHealth.archives().isEmpty {
                        Text("已有 \(DiagHealth.archives().count) 份存档 · 最早 \(DiagHealth.archives().last?.at ?? "")")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                // 158 历次分数回看: 最新在前, 最多列 8 条。差值只跟**上一次**比 (列表里的相邻一条),
                // 不与历史最高/平均比 —— 体检项数变化过 (9 项收口前后), 跨代比较会把"项数变了"读成"身体好了坏了"。
                let arch = DiagHealth.archives()
                if !arch.isEmpty {
                    ForEach(Array(arch.prefix(8).enumerated()), id: \.offset) { idx, a in
                        let prev = idx + 1 < arch.count ? arch[idx + 1].score : nil
                        let pending = a.lines.filter { $0.hasPrefix("待处理") }.count
                        HStack(spacing: DS.Space.s) {
                            Text(a.at)
                                .vkFont(.caption).monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                            if let p = prev {
                                let d = a.score - p
                                Text(d == 0 ? "持平" : (d > 0 ? "+\(d)" : "\(d)"))
                                    .vkFont(.caption2, weight: .semibold).monospacedDigit()
                                    .foregroundStyle(d > 0 ? DS.Palette.ok : (d < 0 ? DS.Palette.danger : DS.Palette.textSub))
                            }
                            Spacer(minLength: DS.Space.s)
                            if pending > 0 {
                                Text("待处理 \(pending) 项")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.warn)
                            }
                            Text("\(a.score) / 100")
                                .vkFont(.caption, weight: .semibold).monospacedDigit()
                                .foregroundStyle(DS.Palette.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("历史只列分数本身, 不画趋势图 —— 存档跨过体检项数变化的那段时, 折线会把「多了一项」读成体检好坏的起伏。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 152/750/751/752 存储构成 · 完整性自查 · 日志保留策略 · 清理前备份提醒
            Section("存储与数据") {   // 152/750/751 存储与数据
                let slices = DataHealth.composition()
                let totalBytes = slices.reduce(0) { $0 + $1.bytes }
                ForEach(slices) { s in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.s) {
                            Text(s.name).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
                            Spacer(minLength: DS.Space.s)
                            Text(DataHealth.human(s.bytes))
                                .vkFont(.caption).monospacedDigit().foregroundStyle(DS.Palette.textSub)
                        }
                        // 构成条本体: 装饰性, 数值已由上面的文本给出 → 对读屏隐藏, 避免"一条 6pt 胶囊"被朗读
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.Palette.surfaceAlt)
                                Capsule()
                                    .fill(DS.Palette.accent)
                                    .frame(width: totalBytes > 0 ? max(2, g.size.width * CGFloat(s.bytes) / CGFloat(totalBytes)) : 2)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("合计 \(DataHealth.human(totalBytes)) — 按本机键值大小估算，不是磁盘真实占用（UserDefaults 有对齐与元数据开销）。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                Button("完整性自查") { integrityReport = DataHealth.integrity() }   // 750 完整性自查
                    .vkFont(.footnote, weight: .medium).foregroundStyle(DS.Palette.accentText)
                if !integrityReport.isEmpty {
                    ForEach(integrityReport, id: \.self) { line in
                        Text(line).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Picker("运行日志保留", selection: Binding(   // 751 运行日志保留
                    get: { DB.store.getString(DiagLogs.retentionKey) },
                    set: { v in
                        // 751: 切档先算"将删条数" → 有东西要删就二次确认, 确认后立即裁剪;
                        // 不需要删 (或切回全部保留) 就直接落键。选值未落键前 Picker 界面自会回弹。
                        let days = v.isEmpty ? nil : Int(v)
                        let n = DiagLogs.pruneCount(days: days)
                        if n == 0 {
                            DB.store.set(DiagLogs.retentionKey, v)
                            app.showToast(days == nil ? "保留策略已改为全部保留"
                                                      : "保留策略已改为近 \(days!) 天 — 没有日志需要删除")
                        } else {
                            retentionAsk = (v, n)
                        }
                    })) {
                    Text("全部保留").tag("")
                    Text("365 天").tag("365")
                    Text("90 天").tag("90")
                }
                .alert("切换日志保留策略？", isPresented: Binding(
                    get: { retentionAsk != nil },
                    set: { if !$0 { retentionAsk = nil } })) {
                    Button("删除并切换", role: .destructive) {
                        if let ask = retentionAsk {
                            DB.store.set(DiagLogs.retentionKey, ask.0)
                            let n = DiagLogs.pruneNow()
                            app.showToast(n > 0 ? "已按新保留期删除 \(n) 条日志" : "没有日志需要删除")
                        }
                    }
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("按新保留期计算，将立即删除 \(retentionAsk?.1 ?? 0) 条已写下的日志（不可恢复）；取消则不改任何东西。")   // 751 按新保留期计算
                }
                Text("切到较短保留期会先报「将删条数」并等确认，确认后立即删除；选「全部保留」不删任何东西。")   // 751 切到较短保留期会先报
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s) {
                    Button("清理空值键位") { guardOrBackup {
                        let r = DataHealth.vacuum()
                        MaintenanceLog.record("清理空值键位")   // 387
                        app.showToast(r)
                    } }
                        .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                    Button("归档一年以上日志") { guardOrBackup {
                        let n = DataHealth.archiveOldLogs()
                        if n > 0 { MaintenanceLog.record("归档旧日志 \(n) 条") }   // 387
                        app.showToast("已归档 \(n) 条")
                    } }
                        .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                    // 452: 无主凭证的隔离出口 —— 上面"孤儿数据"只报不处理, 这里给它一个可点的动作。
                    // 不套 guardOrBackup: 动作是入回收站 (reclaimDays 内可 365/504 取回), 不是删除。
                    Button("隔离无主凭证") {   // 452 隔离无主凭证
                        let n = DataHealth.quarantineOrphanCredentials()
                        if n > 0 { MaintenanceLog.record("隔离无主凭证 \(n) 条") }   // 387
                        app.showToast(n > 0
                            ? "已隔离 \(n) 条无主凭证 (移入回收站, \(CredentialOrg.reclaimDays()) 天内可取回)"
                            : "没有指向已删成员的无主凭证")
                    }
                        .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                }
                // 223 归档的开关档: 原句要求归档能关 —— 这一档此前不存在, 归档只有手动按钮一条路。
                // 开关只管启动时的自动归档; 手动按钮任何时候都可点 (它本身就是一次明确的动作)。
                VariantToggle("启动时自动归档一年以上日志", isOn: Binding(   // 223 启动时自动归档一年以
                    get: { DB.store.getBool("kf_diag_autoarchive") },
                    set: { DB.store.set("kf_diag_autoarchive", $0) }))
                Text("开着时每次冷启动顺手归档一次 (走与按钮同一引擎, 动作进维护回执); 关掉后只有点按钮才归档。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 223: 归档区大小此前无处可看 (archivedCount 全库零调用), 只报"移了多少条"等于看不见结果
                LabeledRow("已归档日志",   // 223 已归档日志
                           "\(DataHealth.archivedCount(app.currentMac)) 条"
                           + (DataHealth.archivedCount(app.currentMac) > 0 ? " · 每锁上限 400 条, 超出丢最旧" : " · 尚无超过一年的日志"))
                // 451 空洞日期: 只报两侧都有数据的天 (引擎内已过滤), 首尾未拉取不算缺口
                Group {
                    let gaps = DataHealth.gapDays(mac: app.currentMac)
                    if gaps.isEmpty {
                        Text("近 14 天日志覆盖没有整天空洞")   // 451 天日志覆盖没有整天空
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("近 14 天有 \(gaps.count) 天整天没有日志: " + gaps.joined(separator: " "))
                            .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("空洞通常意味着那几天没连过锁 (日志只在读取/操作时产生), 不等于数据丢了。")
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 749 待补拉日期段: 与上面 451 同一展示制式, 但它是**新增的一段** ——
                // 451 说"哪几天整天空着", 这里给"要补拉哪几段", 并把序号断档作为**另一条信号**单列,
                // 两条绝不相加成一个数字。锁端不提供缺口清单、协议也没有"锁内上报总数"字段
                // (实读 vendor/app/utils/status.js:100-101 与键表 :11-19, 详见 DiagKit 的 749 段注释),
                // 所以下面每一行都是本机推断、每一行都带"约", 这里也不出现任何对账条数。
                Group {
                    let r = RecordReconcile.pendingPull(mac: app.currentMac)
                    LabeledRow("待补拉日期段", pullCoverLine(r))   // 749 待补拉日期段
                    if r.noLogs {
                        Text("待补拉清单要连着锁拉过一次日志才推得出来。本机现在一行日志都没有, 所以这里一行都不列 —— 没有数就不画数。")   // 749 待补拉清单要连着锁拉
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if r.firstDay == nil {
                            Text("这些行的锁端时刻都是占位值 (lockTime 0 换算过来正好是协议纪元 2010-01-01), 按本仓既有判据一律排除 (StatsKit.dateOf), 所以日期段推不出来 —— 宁可空着也不画假日期。")   // 749 这些行的锁端时刻都是
                                .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if r.singleDay {
                            Text("本机日志只覆盖一天 — 中段空洞的定义要求前后两侧都有数据, 一天推不出任何日期段。")   // 749 本机日志只覆盖一天
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if r.segments.isEmpty {
                            Text("覆盖区间内没有整天缺日志的日期段 — 序号断档是另一条信号, 单列在下面。")   // 749 覆盖区间内没有整天缺
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(r.segments) { s in
                                pullGapRow(s, tag: "", icon: "calendar.badge.exclamationmark")
                            }
                            Text("合计约 \(r.missingDayTotal) 天 (本机天, 不是锁端条数) · 列出最近 \(r.segments.count) 段"
                                 + (r.segmentsHidden > 0 ? " · 另有 \(r.segmentsHidden) 段未列出" : ""))
                                .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 749 跨度上限如实播报: 没扫到的部分不能让人以为是"没有"
                        if r.windowed {
                            Text("本机覆盖跨度超过 \(RecordReconcile.defaultMaxSpanDays) 天, 这里只扫了最近这一段 — 更早的日期段没算进来。")   // 749 本机覆盖跨度超过
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 749 尾段单列: 它只有前一侧有依据, 混进上面的空洞就成了越界推断
                        if let t = r.tail {
                            pullGapRow(t, tag: "尾段 ", icon: "hourglass")
                            Text("尾段与前面的空洞不是一回事: 它后面到昨天都没有可比对的一侧, 这些天完全可能是锁上根本没事件。")   // 749 尾段与前面的空洞不是
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 749 信号 B: 序号断档 —— 单独一条线, 与"哪几天缺日志"分开表述
                        if r.idxGapTotal == 0 && r.idxAnomalies == 0 {
                            Text("序号连续: 本机相邻两行之间没有空号。")   // 749 序号连续
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if r.idxGapTotal == 0 {
                            Text("本机相邻行之间的序号差全都超过了报号上限 — 一个号数都不报, 只出下面那一行。")   // 749 本机相邻行之间的序号
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(r.idxGaps) { g in
                                idxGapRow(g)
                            }
                            Text("序号这条线与日期是两回事: 本机相邻两行之间共 \(r.idxGapTotal) 处断档, 空号合计 \(r.idxGapSkippedTotal) 个 —— 那只是本机序号的算术, 既可能是那几条没拉到、也可能是缓存 300 行上限把旧行挤掉了, 它不等于「锁内少了几条」, 也不和上面的天数加在一起。")   // 749 序号这条线与日期是两
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if r.idxAnomalies > 0 {
                            Text("另有 \(r.idxAnomalies) 处序号跳变超过 \(RecordReconcile.idxGapCap) 个号 (多为翻页游标边界或锁端重排), 按本条纪律只计数、不报号数。")   // 749 另有
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if r.clocklessRows > 0 {
                            Text("日期推断已排除 \(r.clocklessRows) 行没有有效锁端时刻的日志。")   // 749 日期推断已排除
                                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            UIPasteboard.general.string = RecordReconcile.plainLine(r, name: app.displayName)
                            app.showToast("待补拉清单已复制")   // 749 待补拉清单已复制
                        } label: {
                            Label("复制待补拉清单", systemImage: "doc.on.doc")   // 749 复制待补拉清单
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(DS.Palette.accentText)
                        .accessibilityLabel("复制待补拉清单")
                        // 749 补拉要到场
                        // 749 补拉要到场
                        Text("补拉要到场: 本 App 与门锁只有蓝牙直连, 不能远程向锁要历史 —— 到场连上门锁后在「记录」页翻页取回。也先说清代价: 锁端日志有上限会滚动, 被新记录顶掉的那几天补拉也取不回来, 所以这份清单是**待补拉的候选**, 不是「锁里一定还有」的保证。")
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("锁内上报总数在协议里没有对应字段 (证据 vendor/app/utils/status.js:100-101): 03 状态的 21-29 是 PIN/密码/指纹三族凭证槽位的容量与剩余数, 各自再带一枚绑定数/最大长度/批号; 16 日志响应只报本次游标之后的剩余条数。逐键语义在本页「诊断查阅 › 协议字段字典」里同一份表可核 — 所以这里给不出「日志行数 vs 锁内总数」那种对账数字, 上面整份清单都是本机推断。")   // 754 锁内上报总数在协议里
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 752 清理前提醒: 走的是销毁流程同一条备份闸口径, 不另造判断
                if !DestroyKit.backupGatePass {
                    Text("最近 7 天没有备份 —— 清理/归档前建议先导出备份；此处只提示，不拦你。")
                        .vkFont(.caption).foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 511 数据事件: 与备份页同一份 kf_bk_events 台账 (导出/恢复/迁移节点), 清理现场也看得见
            let bkEvents511 = BackupStudio.dataEvents()
            if !bkEvents511.isEmpty {
                Section("数据事件") {   // 511 数据事件
                    ForEach(bkEvents511, id: \.self) { s in
                        Text(s).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    Text("最近 12 个导出 / 恢复 / 迁移节点, 与备份页同源 (kf_bk_events); 只在做过备份类操作后出现。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 284 空间回收建议: 只读数、只给建议。删除动作全部留在上面那一节的既有二次确认里。
            Section("空间回收建议") {   // 284 空间回收建议
                let tips = Recovery.tips()
                if tips.isEmpty {
                    Text("没有值得回收的项 —— 各键族都在阈值以下，或对应数据本来就是空的。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(tips) { t in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(t.title).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
                        // 2026-10-14 走查: RecoveryTip.detail 是 String 变量, 有几条带 `**…**`
                        // (DiagKit 的 storefail / rollback 两条), Text 不解析 Markdown ⇒ 会显示两颗星。
                        mdText(t.detail)
                            .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        if !t.goto.isEmpty {
                            Text("去处: \(t.goto)")
                                .vkFont(.caption2).foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("体积口径: 「回滚快照」那一条是真实文件大小；其余按 kf_* 键值长度估算，不等于磁盘真实占用。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 280 性能面板 (自统计, 默认关) + 215 冷启动打点
            Section("性能面板") {   // 215/280 性能面板
                VariantToggle("采集页面打开耗时", isOn: Binding(
                    get: { pageTraceOn },
                    set: { PageTrace.setOn($0); pageTraceOn = $0 }))
                Text("口径: 从切 Tab 到该页出现之间走过的墙钟时间。只是参考下界 —— SwiftUI 的布局与绘制不完全落在这两点之间, 也不含蓝牙。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                let rows = PageTrace.entries()
                if pageTraceOn && rows.isEmpty {
                    Text("还没攒到样本：切一次页再回来看。配不上起点、或超过 3 秒的样本一律直接丢弃，不猜数。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows.reversed()) { r in
                    LabeledRow(r.name, "\(r.ms) ms · \(PageTrace.clock(r.at))")
                }
                if !rows.isEmpty {
                    Button("清空样本") { PageTrace.clear() }
                        .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                }
                // 215 全仓只有这一处打点, 所以标题不写成"各阶段"
                if let launch = StartupTrace.ms("onLaunch 结束") {
                    LabeledRow("冷启动到 onLaunch 排完",
                               "\(Int(launch)) ms" + (StartupTrace.overBudget ? " · 超 800ms 预算" : " · 在 800ms 预算内"))
                } else {
                    Text("本次启动没记录到 onLaunch 结束打点，没有数就不编数。")   // 215 本次启动没记录到
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                VariantToggle("记录原始收发 hex", isOn: Binding(
                    get: { debugRaw },
                    set: { DB.store.set("kf_debug_raw", $0); debugRaw = $0}))
                // 127 静默排查模式: DiagFlags.silent 有 6 个消费方, 全在 LinkSenseKit ——
                // :75 预握手/自动连接、:122 进页与回前台预热刷新、:150 到场补发、:237 自动重连 tick、
                // :309 275 会话巡检、:417 134 冷启动广播扫描 (第九十一批逐条打开对过行号)。
                // 原文案列的第 7 个"看门狗"是零调用死码, 已删, 计数跟着改 (DiagKit 277 段有说明)。
                // 这些消费方曾长期**没有写入方** ⇒ 这个模式根本打不开, 是下面这条开关把它接真的。
                VariantToggle("静默排查模式", isOn: Binding(   // 127 静默排查模式
                    get: { DiagFlags.silent },
                    set: { DB.store.set("kf_silent_trouble", $0); app.showToast($0
                        ? "已静默: 不再自动回连、预握手与靠近自动开锁; 手动圆盘照常"
                        : "已恢复自动连接与自动开锁") }))
            } footer: {
                Text("协议联调时开启上面的 hex; 平时关闭。\n静默模式只停「自动」的那部分 —— 手动开锁、读取与告警照常，用来复现问题不被后台动作干扰。")
            }
            // 包2/128 环境拥挤度: 冷启动扫描可见设备数的本地结论
            Section {
                LabeledRow("环境拥挤度", LinkSense.envConclusion())   // 128 环境拥挤度
                // 123 扫描强度三档: 只影响发现型扫描 (冷启动/拥挤度清点), 不影响连接与自动开锁时序
                Picker("扫描强度", selection: Binding(   // 123 扫描强度
                    get: { BLEService.ScanProfile.current },
                    set: { DB.store.set(BLEService.ScanProfile.storeKey, $0.rawValue) })) {
                    ForEach(BLEService.ScanProfile.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.menu)
                Text("档位只改变扫描时长与是否接收重复广播；靠近自动开锁与连接重试不受影响。省电档在设备密集环境里可能少扫到几把锁。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                // 128 按最近一次冷启动扫描
                // 134 按最近一次冷启动扫描
                Text("按最近一次冷启动扫描的可见设备数与首台可见耗时本地判断; 冷启动扫描在启动后台自动跑。")
                    .vkFont(.caption)
            }
            // 包2/72 断连原因行: BLE 断连/握手失败事件翻译成人话按时间列出 (数据源 BleTelemetry 流水)
            Section("断连与失败") {   // 72 断连与失败
                if BleTelemetry.events.isEmpty {
                    Text("暂无断连事件 — 连接全程顺畅。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(BleTelemetry.events.prefix(20)) { ev in
                        LabeledRow(ev.what, ev.ok ? "成功" : friendlyFailReason(ev.what))
                    }
                }
            }
            // 156 操作流水: DiagOps 早就在记 (预握手 / 到场补发 / 冷启动扫描, 上限 50 条),
            // 但第九十二批查出 `DiagOps.list()` 全库零调用 —— 记了没人读, 只是往 UserDefaults 里堆。
            // 这里补上出口, 让"记下来"真的能被看到 (与 72 断连流水并列, 同一个开关管)。
            Section {
                let ops = DiagOps.list()
                if ops.isEmpty {
                    Text("暂无操作打点 — 预握手、到场补发与冷启动扫描都会在这里各留一行。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(ops.prefix(20)) { op in
                        LabeledRow(op.t, op.label)
                    }
                }
                // 156 开关：`DiagOps.record` 一直是"先读 isOn 再记"，但全仓没有任何一处写
                // kf_diag_ops_on (默认 true) —— footer 那句"关掉开关即不再记"根本没有开关可关。补真开关。
                VariantToggle("记录操作打点", isOn: Binding(   // 156 记录操作打点
                    get: { DiagOps.isOn() },
                    set: { DB.store.set(DiagOps.on, $0) }))
            } header: {
                Text("操作流水")   // 156 操作流水
            } footer: {
                Text("只留最近 \(DiagOps.maxCount) 条；关掉上面这枚开关即不再记。")   // 156 只留最近
                    .vkFont(.caption)
            }
            // 866 极限字号自检: 原句要求入口在诊断页; 溢出控件无枚举 API, 如实定位为目检
            Section {
                VariantToggle("极限字号自检 (以 200% 字号预览)", isOn: Binding(
                    get: { AXFlags.bigPreview },
                    // 2026-10-15 走查: 这里原先是 `DB.store.set("kf_ax_bigpreview", $0)` 直接落盘 ——
                    // 同一个键在无障碍页走的是 `app.setUnlockOption` (那一条会 bump 种子)，这第二条什么都不推
                    // ⇒ 在这页拨完，根上那枚 `.dynamicTypeSize` 要等下一次别的重建才跟上，看着就是"拨了没作用"。
                    // 同一状态两个通道必已不一致 (本仓反复实撞那一族)，这里统一走 setUnlockOption 那一个口。
                    set: { app.setUnlockOption("kf_ax_bigpreview", $0) }))
                LabeledRow("命中域", "可点控件全 App 下限 44pt (DS.Hit.min); 时间线认领区加余量到 60pt; 圆盘外沿再留 10pt")   // 871 命中域
            } header: {
                Text("渲染自检")   // 866 渲染自检
            } footer: {
                Text("自测开关, 检查后请关回 (与无障碍页同一键位)。溢出控件无法程序枚举, 请开启后逐页目检大字下是否截断/换行。")
                    .vkFont(.caption)
            }
            // 133 蓝牙堆栈急救: 连续 GATT/连接失败后给出 关开蓝牙/重启手机 分步指引
            if failsInLast20 >= 3 {
                Section {
                    LabeledRow("第 1 步", "到 控制中心 关闭再打开系统蓝牙, 等 10 秒回设备页")
                    LabeledRow("第 2 步", "仍失败: 到 设置 → 蓝牙 关闭 App 后台后重新打开本 App")
                    LabeledRow("第 3 步", "仍失败: 重启手机后再试 (蓝牙堆栈异常的重启大法)")
                } header: {
                    Text("蓝牙急救")   // 133 蓝牙急救
                } footer: {
                    Text("近 20 条断连事件中有 \(failsInLast20) 条失败 — 建议按序执行。")
                        .vkFont(.caption)
                }
            }
            // 靠近自动开锁 (AUTOOPEN): 上次拒开原因行 (读 kf_autoopen_audit_, 只记哪道门拒了, 永不记密钥材料)
            if let last = AutoOpen.lastReject(app.currentMac), !app.currentMac.isEmpty {
                Section {
                    LabeledRow("上次拒开原因", last.reason)
                    if AutoOpen.audits(app.currentMac).count > 1 {
                        LabeledRow("更早拒开", AutoOpen.recent(app.currentMac, 3).dropFirst().map { $0.at + " " + $0.reason }.joined(separator: " / "))
                            .accessibilityLabel("更早拒开记录")
                    }
                } header: {
                    Text("靠近自动开锁")
                } footer: {
                    Text("审计只记「哪道门拒了」与时刻, 永不落 ekey/skey 明文; 尾段 500 条。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 455 指令重放摘要: 数据源直接取现有内存日志里 `命令名 -> rc=N` 这一族行 ——
            // 不另建一份流水, 免得两份记录早晚对不上 (行内只有命令名与结果码, 不含帧、密钥或口令)。
            Section("指令流水 (最近 \(min(cmdTrace.count, 20)) 条)") {   // 455 指令流水
                if cmdTrace.isEmpty {
                    Text("本次会话还没有指令结果 — 做一次开锁/读取后这里才有内容。")
                        .vkFont(.footnote).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(cmdTrace.prefix(20).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: DS.Space.s) {
                            Text(line)
                                .vkFont(.caption.monospaced())
                                // 283: rc != 0 的指令行标红 (判据见 cmdTone)
                                .foregroundStyle(Self.cmdTone(line))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            // 159 跳转出口: 每行 rc 一点就落到错误码对照表; 抠到 rc 值就聚焦那一行。
                            // 不用整行 NavigationLink 是因为会吃掉上面 textSelection 的复制手势 —— 两个能力都留。
                            NavigationLink {
                                DiagReferenceView(highlightRC: Self.rcOf(line)).environmentObject(app)
                            } label: {
                                Image(systemName: "text.book.closed")
                                    .vkFont(.footnote)
                                    .foregroundStyle(DS.Palette.accentText)
                            }
                            .accessibilityLabel("查错误码对照表")   // 159 查错误码对照表
                        }
                    }
                    Text("只列命令类型与结果码 (rc)。开启\"记录原始收发 hex\"后, 落进日志的行也只剩帧头 4 位并标注已隐去多少位；完整帧只在内存里留着给\"原始报文\"看，不写盘、不进报告与导出。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 397: 创意写的是 SQLite quick_check, 而本 App 没有 SQLite —— 这一栏做**等价**的三件本地核对, 并且不叫 quick_check。
            Section("本机库体自检") {   // 397 本机库体自检
                Button("立即自检 (只读)") {
                    app.runSelfCheck397()
                    // 手动按下去必须无论结果都有反馈 (解锁路径才做"只在异常时出声")
                    app.showToast(SelfCheck.summary(app.selfCheck397))
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                if app.selfCheck397.isEmpty {
                    Text("解锁时自动跑一次。三项都是本地只读: 库体哈希比对 / 审计链逐条重算 / JSON 回环与台账计数核对。")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(app.selfCheck397.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Image(systemName: l.ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(l.ok ? DS.Palette.ok : DS.Palette.warn)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(l.name)
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Text(l.detail)
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("本 App 的库体在钥匙串与偏好表里, 没有 SQLite —— 这一栏不是 quick_check, 也不重建索引; 它只做上面这三件读检查。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 748 连接成功率 + 756 失败原因分类: 数据源是 BleTelemetry 已留存的真实尝试 (上限 300 条)。
            // 无记录就明说"尚无", 不画 100% 假基线; 口径写"已留存 N 次"而不是滚动天数。
            // 86 失败快照 + 277 看门狗自恢复累计 (同一节, 都是"异常留痕"的读数)
            // 86 失败快照
            // 277 失败快照
            // 285 失败快照
            Section("失败快照 · 会话自恢复 · 扫描时长") {
                // 285 扫描时长自查: 近 7 天每日扫描秒数 + 基于真实累计的省电建议
                let scans = ScanStats.recent(days: 7)
                if !scans.isEmpty {
                    // 2026-10-13 run 63: 原来把 map/joined 全内联进 Text 的字符串拼接, 报 type-check 超时。
                    // 先算好字符串再拼。
                    let scanText = scans.map { s in
                        String(s.day.suffix(5)) + " " + String(Int(s.secs)) + "s"
                    }.joined(separator: " · ")
                    Text("扫描时长: " + scanText)
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ScanStats.advice())
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("会话自恢复", "\(DB.store.getInt("kf_wd_heals", 0)) 次")   // 277 会话自恢复
                Text("会话假死被巡检判定并重新握手成功的累计次数; 明细在运行日志的「会话重协商」行。")   // 275/131 会话假死被巡检判定并
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                let snaps = DB.failEvents(app.currentMac).prefix(10)
                if snaps.isEmpty {
                    Text("还没有失败留痕 — 每次开锁失败会在这里留下信号/电量/错误码 (早先的旧记录只有原因文案)。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(snaps.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(Date(timeIntervalSince1970: s.ts).formatted(date: .abbreviated, time: .shortened)
                                 + " · " + s.msg)
                                .vkFont(.caption).foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            let bits = [s.rssi.map { "RSSI \($0) dBm" },
                                        s.pct.map { "电量 \($0)%" },
                                        s.rc.map { "rc \($0)" }].compactMap { $0 }
                            Text(bits.isEmpty ? "该条为旧记录, 当时未留信号/电量/错误码" : bits.joined(separator: " · "))
                                .vkFont(.caption2)
                                .foregroundStyle(bits.isEmpty ? DS.Palette.textSub : DS.Palette.warn)
                        }
                    }
                }
            }
            Section("连接成功率") {   // 748 连接成功率
                if let rate = BleTelemetry.successRate() {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Text("\(rate.pct)%")
                            .vkFont(.title2, weight: .semibold)
                            .foregroundStyle(DS.Palette.text)
                            .monospacedDigit()
                        Text("已留存 \(rate.total) 次连接尝试, 成功 \(rate.ok)")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    let daily = BleTelemetry.dailyRates()
                    if daily.count >= 2 {
                        Chart(daily) { p in
                            LineMark(x: .value("日期", p.day), y: .value("成功率", p.pct))
                            PointMark(x: .value("日期", p.day), y: .value("成功率", p.pct))
                                .annotation(position: .top) { Text("\(p.n)").vkFont(.caption2) }
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 150)
                        .accessibilityLabel("按日连接成功率趋势, 共 \(daily.count) 天")
                    } else {
                        Text("按日趋势需至少 2 天记录 — 当前只有一天 (\(daily.count))")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    Text("尚无连接尝试记录 — 做过扫描/开锁后这里才有数据")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
                ForEach(BleTelemetry.failClasses(), id: \.name) { c in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Text(c.name).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
                        Text("\(c.n) 次").vkFont(.footnote).foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: DS.Space.m)
                        Text(c.hint).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("运行日志 (最新在末尾) · 显示 \(logRows.count)/\(app.lock.logs.count) 条") {
                // 153 级别过滤 (取自日志行自带的 [level]) + 154 关键词高亮
                HStack(spacing: DS.Space.xs) {
                    ForEach(["", "info", "warn", "error"], id: \.self) { lv in
                        let on = logLevelFilter == lv
                        Button(lv.isEmpty ? "全部" : lv) {
                            logLevelFilter = lv
                            DS.Haptics.tick.impactOccurred()
                        }
                        .vkFont(.caption.weight(on ? .semibold : .regular))
                        .padding(.horizontal, DS.Space.s).padding(.vertical, 4)
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
                        .frame(minHeight: DS.Hit.min - DS.Space.xs)
                        .contentShape(Rectangle())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("日志级别过滤: \(logLevelFilter.isEmpty ? "全部" : logLevelFilter)")
                HStack(spacing: DS.Space.s) {
                    TextField("搜索日志", text: $logQuery)   // 154 搜索日志
                        .autocorrectionDisabled()
                        .vkFont(.caption)
                        .accessibilityLabel("日志关键词搜索")
                    if !logQuery.isEmpty {
                        Button("清空") { logQuery = "" }
                            .vkFont(.caption).foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                }
                // 542 时间窗刷选: 顶部 24 小时刻度条, **按住拖动**选一段小时窗 ——
                // 原句要的是"拖动选择查看时间窗", 不是 730 那种逐小时点选; 判据只看行首时间戳的小时位。
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text("时间窗")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                        if let a = winFrom, let b = winTo {
                            Text("\(min(a, b))–\(max(a, b)) 时")
                                .vkFont(.caption2.monospacedDigit())
                                .foregroundStyle(DS.Palette.accentText)
                            Button("清除") { winFrom = nil; winTo = nil }
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min - DS.Space.s)
                                // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                                // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        } else {
                            Text("按住刻度拖动选择小时段")   // 542 按住刻度拖动选择小时
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer(minLength: 0)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Palette.surfaceAlt).frame(height: 12)
                            if let a = winFrom, let b = winTo {
                                let lo = min(a, b), hi = max(a, b)
                                Capsule().fill(DS.Palette.accent.opacity(0.45))
                                    .frame(width: max(8, w * CGFloat(hi - lo + 1) / 24), height: 12)
                                    .offset(x: w * CGFloat(lo) / 24)
                            }
                        }
                        .frame(height: 12)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    let h = min(23, max(0, Int(v.location.x / max(w, 1) * 24)))
                                    if !winDragging { winDragging = true; winFrom = h; winTo = h } else { winTo = h }
                                }
                                .onEnded { _ in winDragging = false }
                        )
                    }
                    .frame(height: 12)
                    .accessibilityElement()
                    .accessibilityLabel(winFrom == nil
                        ? "日志时间窗刻度条, 按住拖动选择小时段"
                        : "日志时间窗 \(min(winFrom ?? 0, winTo ?? 0)) 到 \(max(winFrom ?? 0, winTo ?? 0)) 时")
                }
                if logRows.isEmpty && !app.lock.logs.isEmpty {
                    Text("当前过滤条件下没有匹配行（共 \(app.lock.logs.count) 条日志）。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if logRows.isEmpty && app.lock.logs.isEmpty {
                    // 包14 空态族 (814/815/841): GuidedEmptyView 此前整族零调用 —— 它有双按钮/进度点/小管家
                    // 的参数, 但旧 init 只收三个必填, 参数传不进去, 所以这里换成它才算真接上。
                    // 819 诊断首跑按钮 = 这个空态的主按钮「跑一键体检」: 首次进入以一个动作代替空列表,
                    // 而不是只留一句"还没有日志"。它调的就是页面顶部那个 rerunAll(), 不另起一套体检流程。
                    GuidedEmptyView(systemImage: "tray",
                                    title: "还没有运行日志",
                                    message: "做一次连接、开锁或读取操作, 这里就会出现记录。也可以先跑一遍体检, 看本机环境是否就绪。",
                                    step: logGuideStep,
                                    stepTotal: 3,
                                    primaryTitle: "跑一键体检",
                                    primary: { rerunAll() },
                                    secondaryTitle: "去设备页操作",
                                    secondary: { app.requestRoute(.device); dismiss() },   // 收掉这一层 (sheet 或 push) 才看得见切好的 Tab
                                    mascot: true)
                        .listRowInsets(EdgeInsets())
                    // 818 日志来源说明: 空态不只说"还没有", 还说出**哪四类**会进这里。
                    // 名单就是本页自己那四个分区 —— 不在这里另编一套分类法; 两套分类迟早对不上,
                    // 而对不上的代价是"用户按说明去操作, 结果出现在另一栏里"。
                    // 图标全部沿用本仓已在用的名字 (不臆造 systemName: 名字错了只会在真机上显示空白)。
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(Array([("运行日志", "list.bullet.rectangle"),
                                       ("指令结果", "text.bubble"),
                                       ("断连事件", "bell.badge"),
                                       ("操作打点", "stopwatch")].enumerated()), id: \.offset) { _, s in
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: s.1)
                                    .font(.system(size: DS.Icon.xs))
                                Text(s.0).vkFont(.caption2)
                            }
                            .foregroundStyle(DS.Palette.textSub)
                        }
                        Text("做一次连接、开锁或读取, 四类里对应的那几栏就会开始积累。")   // 818 做一次连接
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DS.Space.s)
                    .accessibilityElement(children: .combine)
                }
                // 543 计数: 只报当前过滤后可见行里的引用行数, 不报全库 (与上面的 显示 x/y 同一口径)
                if entityRows > 0 {
                    Text("当前视图有 \(entityRows) 行含可跳转的凭证/指纹引用")   // 543 当前视图有
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(logRows) { row in
                    let ents = DiagLogs.entities(in: row.line)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        highlighted(row.line, base: Self.logTone(row.line))
                            .vkFont(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            // 740 原始报文查看: HexDump 此前全库无消费者, 这里接成长按入口 (用菜单而非点击,
                            // 不与 textSelection 抢手势)
                            .contextMenu {
                                Button { dumpedLine = row } label: {
                                    Label("查看原始报文", systemImage: "text.alignleft")
                                }
                                .disabled(Self.hexOf(row.line).isEmpty)
                                if !Self.hexOf(row.line).isEmpty {
                                    // 有完整帧就按完整帧报字节数; 只报脱敏残片会让人以为帧只有 2 字节
                                    Text("该行帧约 \(max(Self.hexOf(rawFrame(of: row.line)), Self.hexOf(row.line)).count / 2) 字节"
                                        + (rawFrame(of: row.line).isEmpty ? " (仅帧头留存)" : ""))
                                        .vkFont(.caption2)
                                }
                            }
                        if !ents.isEmpty {
                            HStack(spacing: DS.Space.xs) {
                                ForEach(ents) { e in
                                    Button {
                                        entityRef = e
                                        DS.Haptics.tick.impactOccurred()
                                    } label: {
                                        Text(e.text)
                                            .vkFont(.caption2, weight: .medium)
                                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
                                            .foregroundStyle(DS.Palette.accentText)
                                            .variantPlate(DS.Palette.surfaceAlt, .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(minHeight: DS.Hit.min - DS.Space.xs)
                                    .accessibilityLabel("查看\(e.text)的本机台账信息")
                                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 22.6pt (< 44)。
                                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                    .frame(minHeight: DS.Hit.min)
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $dumpedLine) { row in
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("原始报文").vkFont(.headline).foregroundStyle(DS.Palette.text)   // 740 原始报文
                Text(row.line).vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    // 优先展示内存里的完整帧 (此前这里只会 dump 日志行的脱敏残片 = 帧头 4 位,
                    // 一个 40+ 字节的帧只剩 2 字节, "查看原始报文"名不副实)
                    let hx = rawFrame(of: row.line).isEmpty ? Self.hexOf(row.line) : rawFrame(of: row.line)
                    let pf = FrameFields.parse(hx)   // 740 字段解析
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        // 完整帧 (含 skey/ekey/PIN 明文): 录屏遮罩已随本轮删减移除,
                        // 这条 374 防护不再有 —— 界面照常显示, 但复制走仍是刻意禁止的 (见下)。
                        Text(HexDump.dump(hx))
                            .vkFont(.caption.monospaced())
                            .foregroundStyle(DS.Palette.text)
                            // 刻意不给 textSelection: 完整帧里带 skey/ekey/PIN 明文, 可以看不可以复制走
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !pf.rows.isEmpty {
                            Text(String(format: "字段解析 — 帧头 %dB · cmd 0x%02X", pf.header, pf.cmd))   // 740 字段解析
                                .vkFont(.footnote).foregroundStyle(DS.Palette.textSub)
                            ForEach(Array(pf.rows.enumerated()), id: \.offset) { _, f in
                                LabeledRow(f.0, f.1)
                            }
                        }
                    }
                    .padding(DS.Space.m)
                }
                Text(rawFrame(of: row.line).isEmpty
                     ? "这一行没有可还原的完整帧 (只留了脱敏后的帧头)。"
                     : "完整帧含密钥与口令明文：只在屏幕显示，不能选中复制，也不写进任何报告或导出。请别截图外传。")
                    .vkFont(.caption2)
                    .foregroundStyle(rawFrame(of: row.line).isEmpty ? DS.Palette.textSub : DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                Button("完成") { dumpedLine = nil }
                    .buttonStyle(PrimaryActionStyle())
            }
            .padding(DS.Space.l)
            .presentationDetents([.medium, .large])
        }
        // 543 实体跳转: 弹出本机台账元数据。LedgerPwd.pwd 存的是口令明文, 只读备注/属主/有效期这些元数据字段
        .sheet(item: $entityRef) { ref in
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(ref.text).vkFont(.headline).foregroundStyle(DS.Palette.text)
                Text(DiagLogs.entityDetail(ref, mac: app.currentMac))
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这里只显示台账元数据 (备注/属主/有效期)。口令、指纹特征与密钥不会出现在日志和本页。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.m) {
                    Button("关闭") { entityRef = nil }
                        .vkFont(.subheadline).foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                    if ref.isCredential {
                        // 543 深链: 切 Tab 前挂上定位载荷; 跨锁由 pendingCredNavMac 在消费端先切锁 (与 577 同一条链)
                        Button("到凭证页查看") {
                            entityRef = nil
                            switch ref.kind {
                            case .pwd(let a): app.pendingCredNav = "pwd:\(a)"
                            case .fp(let b): app.pendingCredNav = "fp:\(b)"
                            default: break
                            }
                            app.pendingCredNavMac = app.currentMac
                            app.requestRoute(.credentials)   // 2026-10-14 走查: 同上一处, 本页可从设备页进入
                            dismiss()           // 2026-10-15 走查: 同上 —— requestTab 只过访客门禁，不收这层 sheet/push 就看不见切好的 Tab
                        }
                        .buttonStyle(PrimaryActionStyle())
                    }
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 本页已不止日志: 体检/连接质量/原始报文/急救都在此, 标题按实际范围改
        .navigationTitle("诊断与运行日志")
        .variantList()
        .dsScreenBackground()
        .task { if results.isEmpty { rerunAll() } }   // 149 进页即出分 (纯本地读, 不发包)
    }

    /// 740: 从一行日志里取出 `hex=` 之后的连续十六进制串 (与 LockService 的 Redact.frameHex 同口径);
    /// 未开"记录原始收发 hex"时日志不含帧 → 返回空串, 入口自动禁用。
    /// 239: 把报告渲染成一张带时间水印的图 (ImageRenderer, iOS 16+)。宽度固定 720pt / 2x,
    /// 报告多长图就多长; 水印落在右下角对角线上 (低透明度, 不挡正文)。
    @MainActor
    private func renderDiagShot() -> UIImage? {
        let now = Date()
        let card = VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("离线锁管家 · 诊断摘要")
                .vkFont(.headline)
            Text(report())
                .vkFont(.caption2.monospaced())   // 语义字号: 固定 pt 不参与 Dynamic Type 缩放
                .fixedSize(horizontal: false, vertical: true)
            Text("导出时间 " + now.formatted(date: .abbreviated, time: .standard) + " · 本图由 App 本机生成")   // 239 本图由
                .vkFont(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 720, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottomTrailing) {
            Text("离线锁管家 " + now.formatted(date: .numeric, time: .shortened))
                .vkFont(.caption2)
                .foregroundStyle(Color.black.opacity(0.32))
                .rotationEffect(.degrees(-18))
                .padding(DS.Space.xxl)
        }
        // 2026-10-14 走查: 这张卡是**硬白底**, 但里面三行 Text 都没写前景色 ⇒ 吃环境的主文本色。
        // 深色档下主文本色是浅色, 白底白字 = 导出的诊断图整段看不见。ImageRenderer 默认环境
        // 目前是浅色, 但那是"默认"不是"保证"; 把口径写死在这里, 这张图永远按浅色出。
        // 位置必须在**最外层**: `.environment` 只作用于它下面的子树, 挂在 `.overlay` 之前
        // 就漏掉了水印那一层 (它的颜色是写死的黑 0.32, 今天不受影响, 但别留下这个坑)。
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: card)
        r.scale = 2
        return r.uiImage
    }
    /// 542: 取日志行里第一个 "HH:mm" 的两位小时 (行首可能是 "yyyy-MM-dd HH:mm:ss" 也可能是 "HH:mm:ss",
    /// 所以不按固定偏移切, 用模式取第一个合法小时)。取不到返回 nil —— 那种行不进时间窗。
    private static func hourOf(_ line: String) -> Int? {
        let head = String(line.prefix(20))
        guard let r = head.range(of: #"\b([01][0-9]|2[0-3]):[0-5][0-9]"#, options: .regularExpression) else { return nil }
        return Int(head[r].prefix(2))
    }
    /// 283 日志着色: 行内自带级别 → 颜色。判据与 153 的级别过滤用同一份 `[level]` 文本, 不另立第二套。
    /// 错误红 / 警告黄 / 其余正文色。不加图标 —— 行首已有时间戳, 再加符号会把窄行推得更窄。
    private static func logTone(_ line: String) -> Color {
        if line.contains("[error]") { return DS.Palette.danger }
        if line.contains("[warn]") { return DS.Palette.warn }
        return DS.Palette.text
    }
    /// 283 指令流水着色: `命令名 -> rc=N` 里 N != 0 的行标红 (与 455 的行格式同源)。
    private static func cmdTone(_ line: String) -> Color {
        guard let r = line.range(of: "rc=") else { return DS.Palette.text }
        var s = ""
        for c in line[r.upperBound...] {
            if c.isNumber || (c == "-" && s.isEmpty) { s.append(c) } else { break }
        }
        return (Int(s) ?? 0) != 0 ? DS.Palette.danger : DS.Palette.text
    }
    private static func hexOf(_ line: String) -> String {
        guard let r = line.range(of: "hex=") else { return "" }
        var out = ""
        for c in line[r.upperBound...] {
            if c.isHexDigit { out.append(c) } else { break }
        }
        return out
    }

    private struct LogLine: Identifiable {
        let id: String
        let line: String
    }

    /// id 由"日志内容 + 同内容出现次序"构成: 顶部插入新日志时已有行的 id 不变,
    /// 不会像 id: \.offset 那样把所有行的 key 整体位移 (长按选中会跳)。
    /// 153 分级过滤 + 154 关键词高亮: 级别取自日志行自带的 `[level]` 标记 (info/warn/error), 不靠猜。
    private var logRows: [LogLine] {
        var seen: [String: Int] = [:]
        var out: [LogLine] = []
        var src = Array(app.lock.logs.suffix(150))
        if !logLevelFilter.isEmpty {
            src = src.filter { $0.contains("[\(logLevelFilter)]") }
        }
        if !logQuery.isEmpty {
            src = src.filter { $0.localizedCaseInsensitiveContains(logQuery) }
        }
        // 542: 时间窗过滤 (小时段)。与上面两条串联, 互不改各自口径; 取不到小时位的行不进窗。
        if let a = winFrom, let b = winTo {
            let lo = min(a, b), hi = max(a, b)
            src = src.filter { line in
                guard let h = Self.hourOf(line) else { return false }
                return h >= lo && h <= hi
            }
        }
        out.reserveCapacity(src.count)
        for line in src {
            let n = seen[line] ?? 0
            seen[line] = n + 1
            out.append(LogLine(id: line + "#" + String(n), line: line))
        }
        return out
    }
    /// 455: 指令流水 = 内存日志里 `命令名 -> rc=N` 那一族行 (最新在前)。取现成日志而不是另建一份环形队列,
    /// 是因为两份同族记录迟早对不上; 这些行本身只含命令名与结果码。
    private var cmdTrace: [String] {
        app.lock.logs.reversed().filter { $0.contains("-> rc=") }
    }

    /// 159: 从 `命令名 -> rc=N` 行里抠出结果码; 抠不到返回 nil (照常打开对照表, 只是不聚焦)
    private static func rcOf(_ line: String) -> Int? {
        guard let r = line.range(of: "rc=") else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }

    /// 740: 完整帧只存在于 LockService.recentFrames (内存环形, 不写盘)。
    /// 日志行是脱敏后的版本 (`hex=ABCD(n 位已隐去)`), 所以用"脱敏后是否等于该行"反查原帧 —— 这是精确匹配, 不靠时间猜。
    private func rawFrame(of line: String) -> String {
        app.lock.recentFrames.first { Redact.frameHex($0) == line } ?? ""
    }

    /// 543: 可见行里含实体引用的行数 (与 logRows 同一份过滤结果, 不用全库计数骗眼睛)
    private var entityRows: Int {
        logRows.reduce(0) { $0 + (DiagLogs.entities(in: $1.line).isEmpty ? 0 : 1) }
    }

    /// 154 命中处高亮: 只给命中段加粗+主色, 不改文本内容 (复制出来仍是原样)
    private func highlighted(_ line: String, base: Color = DS.Palette.text) -> Text {
        let q = logQuery.trimmingCharacters(in: .whitespaces)
        // 颜色一律写在 run 上: 若在外层再套 foregroundStyle, 命中段的强调色会被整体覆盖 (读码可确定, 不靠试)
        // 283: 基础色改成参数 —— 错误行红/警告行黄必须落在 run 层, 外层套色对这一族无效。
        guard !q.isEmpty, let first = line.range(of: q, options: .caseInsensitive) else {
            return Text(line).foregroundColor(base)
        }
        let pre = String(line[line.startIndex..<first.lowerBound])
        let hit = String(line[first])
        let post = String(line[first.upperBound...])
        // Text + Text 自 iOS 26 弃用。这里改成 AttributedString 逐段上色:
        // 上面 1357 行立的规矩是"颜色只能写在 run 上" —— 插值版若在外层再套 foregroundColor(base),
        // 命中段的强调色会被整体盖掉 (正是那条注释点名的坑), 所以不用插值, 用属性逐段给。
        // bold 走 inlinePresentationIntent, 与 DesignSystem.mdText 同一手法 (仓库内已被 CI 编过)。
        var out = AttributedString()
        for (seg, color, heavy) in [(pre, base, false), (hit, DS.Palette.accentText, true), (post, base, false)] {
            var a = AttributedString(seg)
            a.foregroundColor = color
            if heavy { a.inlinePresentationIntent = .stronglyEmphasized }
            out.append(a)
        }
        return Text(out)
    }

    /// 133: 近 20 条断连事件中的失败条数 (≥3 触发急救块)
    private var failsInLast20: Int { BleTelemetry.events.prefix(20).filter { !$0.ok }.count }

    /// 72: 断连错误码人话翻译 (本地词表, 不改协议层; 124 占用类走保守文案)
    private func friendlyFailReason(_ what: String) -> String {
        if what.contains("超时") { return "握手超时 — " + LinkSense.occupationHint() }
        if what.contains("蓝牙") { return "蓝牙未开/权限缺失 — 系统设置 → 隐私与安全性 → 蓝牙" }
        if what.contains("未发现") { return "不在广播范围 — 走近门锁 1 米内再试" }
        if what.contains("信号弱") { return "RSSI 低于围栏, 本轮跳过预热 (省电策略)" }
        if what.contains("回连") { return "回连轮次失败 — 按 5/15/30/60/90 秒节律重试中" }
        if what.contains("重协商") { return "会话重协商 — 连接挂起过久, 已主动重建握手" }
        return "失败 — 详见运行日志与失败三分类"   // 536 失败
    }

    private func report() -> String {
        var out = "【离线锁管家诊断报告】\n"
        out += "格式: 纯文本分节 (内容都在这一份文本里, 本工程不打包)\n"
        // 299 反馈文案: 原句要的是「用户反馈表单」, 本工程没有表单也没有任何提交口 ——
        // 能给的是把这一行留给你自己改写: 复制后在对话窗口里换成实话, 不填也照样能发。
        out += "问题描述: （把这句换成你遇到的事 — 什么时候 / 点了哪个入口 / 本来期待什么 / 实际发生了什么）\n"
        out += "时间: " + DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium) + "\n"
        out += "App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))\n"
        out += "系统: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)\n"
        // 157 的"设备清单": 列全部已配对锁, 不再只报当前一把 (报给开发者看时, 只有当前锁等于漏掉问题现场)
        let all = DB.keychains()
        if all.isEmpty {
            out += "门锁: 未配对\n"
        } else {
            out += "--- 设备清单 (\(all.count) 把) ---\n"
            for k in all {
                out += "- \(LockArchive.displayName(k)) / mac=\(k.mac) / pid=\(k.pid) / 固件=\(k.fw.isEmpty ? "未读到" : k.fw)\n"
            }
            if let kc = app.current {
                out += "当前锁连接: \(app.lock.connectedMAC == kc.mac ? "已连接" : "未连接")\n"
            }
        }
        if !app.lock.lastError.isEmpty { out += "最近错误: \(app.lock.lastError)\n" }
        // 157 的"体检结果": 本页跑过才写, 没跑过就如实说没跑 —— 不拿空表冒充"全部通过"
        if results.isEmpty {
            out += "--- 体检 ---\n未在本次会话运行体检 (总分与分项因此缺失)\n"
        } else {
            out += "--- 体检 (总分 \(score)) ---\n"
            for it in results {
                out += "- [\(it.ok ? "通过" : "异常")] \(it.name): \(it.detail)\n"
            }
        }
        out += "--- 运行日志 (\(app.lock.logs.count) 条, 取最近 100) ---\n"
        out += app.lock.logs.suffix(100).joined(separator: "\n")
        // 157 补近 7 天留档 (751 保留策略过滤后的本地库; 原来只有本次会话内存行)
        let since = DiagLogs.localDay(WeekCal.shifted(Date(), days: -7))
        let week = DiagLogs.all().filter { $0.date >= since }
        out += "\n--- 近 7 天留档日志 (\(week.count) 条, 取最近 100) ---\n"
        out += week.suffix(100).map { "\($0.date) \($0.time) [\($0.level)] \($0.msg)" }.joined(separator: "\n") + "\n"
        return out
    }
}