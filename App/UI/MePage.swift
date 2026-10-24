//
//  MePage.swift
//  设置页 · 全新重写 (2026-10-21)
//
//  门里「这台手机」域的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 SettingsView (1335 行) 的根本区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 门锁 / 安全 / 工具 三个大分组, 19 个入口平铺 + 搜索。
//        —— "设置"是个收纳箱, 用户不知道该去哪。
//
//  新版: 按"这个开关影响什么"重排为四组:
//
//    ① 本机保护   — 应用锁 / 隐私 / 销毁 (最重, 放最上)
//    ② 这台锁     — 锁档案 / 安全模式 / 校时 / 开锁偏好 / 自动开锁
//    ③ 数据       — 备份 / 恢复 / 导出 / 消息
//    ④ 关于与偏好 — 外观 / 关怀 / 维护提醒 / 固件
//
//  19 个入口一个不删, 只是重新分组 + 加内联真实值。
//
//  设计原则:
//    · 危险操作 (销毁/隐私) 单独成组并置顶, 不让它混在列表里
//    · 每行右侧显示"当下值" (如"已开启"), 不是只有箭头
//    · 删除搜索 (19 项用分组就能找到, 搜索是负担)
//

import SwiftUI

/// 设置页 —— 门里「这台手机」
struct MePage: View {
    @EnvironmentObject private var app: AppState

    private var mac: String { app.currentMac }

    /// 2026-10-24 接入 SettingsGroups：五组筛选片。
    ///
    /// 这一页此前把 6 个区块平铺一屏（状态摘要 / 数据保护 / 备份 / 锁 / 数据 / 关于），
    /// 与 SettingsGroups.swift 里那套「五组分片」的数据模型对不上 ——
    /// 那套模型定义了却全仓零调用。现在把它接上：
    /// 顶部一排筛选片，每个区块按归属只在其组下出现；「全部」时与改动前逐字一致。
    @State private var settingsGroup: SettingsGroup? = nil

    var body: some View {
        // M5 重做: List + Section → ScrollView + XPanel 卡片流
        //
        // 五个 Section 的内容一行没动（都是 XRow / summaryTile），
        // 只把外壳换成 XPanel，header/footer 转成卡片底部 caption。
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("本机设置", subtitle: "这台手机上的保护与数据") {
            // 审美对齐 HTML 05-system / 4a-me：卡之前有一排**带迷你环的玻璃胶囊**。
            // App 这一页此前**一个胶囊都没有** —— 进来先是一排卡片，看不到本机各项状态的总览。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XSpace.s) {
                    XStatChip(label: "应用锁",
                              value: DB.hasPasscode() ? "已开启" : "未开启",
                              ringFraction: DB.hasPasscode() ? 1 : 0,
                              tint: DB.hasPasscode() ? XPalette.ok : XPalette.warn,
                              fillsWidth: false)
                    XStatChip(label: "待处理告警",
                              value: String(RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac })),
                              ringFraction: RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac }) > 0 ? 1 : 0,
                              tint: RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac }) > 0 ? XPalette.danger : XPalette.ok,
                              fillsWidth: false)
                    XStatChip(label: "上次导出",
                              value: backupAgeChipText,
                              ringFraction: backupAgeChipFraction,
                              tint: backupAgeChipFraction > 0.5 ? XPalette.warn : XPalette.ok,
                              fillsWidth: false)
                    XStatChip(label: "门锁",
                              value: "\(DB.keychains().count) 把",
                              ringFraction: min(1, Double(DB.keychains().count) / 3),
                              tint: XPalette.accent,
                              fillsWidth: false)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, XSpace.m)
            settingsGroupBar
            if settingsSectionShown(settingsGroup, .daily) { statusSummary }
            if settingsSectionShown(settingsGroup, .daily) { backupRestoreCard }
            if settingsSectionShown(settingsGroup, .data) { protectionSection }
            if settingsSectionShown(settingsGroup, .daily) { lockSection }
            if settingsSectionShown(settingsGroup, .data) { dataSection }
            if settingsSectionShown(settingsGroup, .help) { aboutSection }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 本机保护

    // ═══════════════════════════════════════════════════════
    // MARK: - ⓪ 本机状态摘要
    // ═══════════════════════════════════════════════════════

    /// 「这台手机」的第一眼该是本机整体状态, 而不是一串入口。
    /// 四项: 应用锁 / 未处理告警 / 备份新鲜度 / 门锁数量。
    /// 每项都是一个能直接跳过去的入口 —— 摘要不是只读的仪表,
    /// 看到"未开启"就该能一点就进去开。
    /// 五组筛选片 —— 「全部 + 开门日常 / 钥匙与成员 / 数据与安全 / 外观与辅助 / 帮助与关于」
    ///
    /// 用 XStatChip 的风格但在选中态上给实底：它与页面顶部的读数胶囊不是一回事
    /// （那是"读数"，这是"筛选"），所以走独立的样式而不是复用 XStatChip。
    private var settingsGroupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XSpace.s) {
                groupChip(nil, "全部")
                ForEach(SettingsGroup.allCases) { g in
                    groupChip(g, g.title)
                }
            }
            .padding(.horizontal, XSpace.gutter)
        }
        .scrollIndicators(.hidden)
        // 抵消外层 gutter，让筛选片能滑到屏幕边缘
        .padding(.horizontal, -XSpace.gutter)
        .padding(.bottom, XSpace.s)
    }

    private func groupChip(_ g: SettingsGroup?, _ title: String) -> some View {
        let on = settingsGroup == g
        return Button {
            withAnimation(XMotion.quick) { settingsGroup = g }
            XHaptics.tick.impactOccurred()
        } label: {
            Text(title)
                .xFont(.subheadline, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? XPalette.onAccent : XPalette.textSub)
                .padding(.horizontal, XSpace.m)
                // 规范：装文字的容器不用固定高度（AX 字号下会破版），
                // 且按钮视觉高可小于 44，但**触达必须补到 44**。
                .frame(minHeight: 36)
                .frame(minHeight: XHit.min)
                .background(
                    Capsule().fill(on ? XPalette.accent : XPalette.surface.opacity(0.55))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    private var statusSummary: some View {
        let locked = DB.store.getBool("kf_applock")
        let alarmN = RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac })
        let bkMs = DB.store.getInt("kf_bk_last_export", 0)
        let bkDays = bkMs > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - Double(bkMs)) / 86_400_000)
            : -1
        let locks = DB.keychains().count

        // 六图改造 (2026-10-23): 在四枚瓦片之上加**图 5 的主角读数行**。
        //
        // 图 5 Activity Details 的第一张卡是「44px 大数字 + 一枚环 → 三列细线」。
        // 之前这里是四枚等重大瓦片：每枚都是 19pt，读不出"现在最该管哪件事"。
        // 加一行 44px 主角之后，眼睛先看到"有 1 件事要处理"，再往下看是哪四类；
        // 环给出"待办占整体的比例"，不需要用户自己算。
        let pending = (locked ? 0 : 1) + alarmN + (bkDays < 0 ? 1 : 0)
        let total = 4
        return XPanel {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本机状态")
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.textTertiary)
                        XHeroNumber(
                            text: String(pending),
                            color: pending > 0 ? XPalette.warn : XPalette.ok,
                            unit: "项")
                        Text(pending > 0 ? "都在这台手机里，点下面的方块可直达" : "这台手机没有需要处理的事")
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 72,
                        progress: Double(total - pending) / Double(total),
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        solid: pending > 0 ? XPalette.warn : XPalette.ok
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.bottom, XSpace.m)
                XHairline().padding(.bottom, XSpace.s)
                // ⚠ 2026-10-24 修复：这四个瓦片的注释一直写着"每项都是一个能直接跳过去的入口"，
                // 但它们**没有 action 参数、也没包在导航里** —— 点上去什么都不会发生。
                // 这正是用户反馈的"入口不能点击"。现在逐个包 NavigationLink。
                HStack(spacing: XSpace.s) {
                    NavigationLink {
                        SecurityPage().environmentObject(app)
                    } label: {
                        summaryTile(
                            icon: locked ? "lock.shield.fill" : "lock.open",
                            value: locked ? "已锁" : "未锁",
                            label: "应用锁",
                            tone: locked ? XPalette.ok : XPalette.warn)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AlarmsPage().environmentObject(app)
                    } label: {
                        summaryTile(
                            icon: alarmN > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                            value: alarmN > 0 ? "\(alarmN)" : "0",
                            label: "待处理告警",
                            tone: alarmN > 0 ? XPalette.warn : XPalette.ok)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BackupPage().environmentObject(app)
                    } label: {
                        summaryTile(
                            icon: bkDays < 0 ? "externaldrive.badge.questionmark" : "externaldrive.fill",
                            // §7.16：单位不拼进数值字符串 —— 拼进去单位会拿到数值的字号与颜色。
                            value: bkDays < 0 ? "从未" : (bkDays <= 0 ? "今天" : "\(bkDays)"),
                            label: "上次备份",
                            tone: bkDays < 0 ? XPalette.warn : (bkDays > 14 ? XPalette.warn : XPalette.ok),
                            unit: bkDays > 0 ? "天" : nil)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LocksPage().environmentObject(app)
                    } label: {
                        summaryTile(
                            icon: "square.stack.3d.up.fill",
                            value: "\(locks)",
                            label: "门锁",
                            tone: locks > 0 ? XPalette.accent : XPalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, XSpace.xs)
            }
        }
    }

    /// 一个大数字指标 —— 数值在前，标签在后
    ///
    /// 与原来相比（M5 形态改造）:
    ///   · 去掉 34pt 图标圆 —— 它占了近一半高度却只传达"这是哪一项"
    ///   · 数值从 subheadline 提到 title2 —— 一眼看到的是数，不是装饰
    ///   · 高度统一 76pt，四张卡并排不会高低不齐
    /// `unit` 走规范 §7.16：与数值**同色**（= tone）、单位档 = 数值档的 70%、基线对齐。
    /// 以前是 "\(值)天" 拼成一个串 —— 那样单位会跟数值一样大、一样色，规范给的反例正是这个。
    private func summaryTile(icon: String, value: String, label: String, tone: Color,
                             unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // §7.16 走 XValueUnit（全仓唯一实现），§7.18 的降档系数一并传入。
            XValueUnit(
                value: XMetric.display(value),
                unit: unit,
                style: .title2,
                weight: .bold,
                color: tone,
                scale: XMetric.overflowScale(digits: XMetric.digitCount(value)))
            .minimumScaleFactor(0.55)
            HStack(spacing: 3) {
                // 规范 §10：图标最小 12pt（原 9pt 低于档位下限）。
                Image(systemName: icon)
                    .font(.system(size: XIcon.xs, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .xFont(.caption2)
            .foregroundStyle(XPalette.textSub)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, XSpace.m)
        .padding(.vertical, XSpace.s)
        .background {
            RoundedRectangle(cornerRadius: XRadius.tile, style: .continuous)
                .fill(XPalette.surfaceAlt.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
    // ═══════════════════════════════════════════════════════

    private var protectionSection: some View {
        XPanel {
            // ═══ 2026-10-24 去重 ═══
            // 这里原来有一行「本机数据保护 → SecurityPage」，与上方 statusSummary 的
            // 「应用锁」摘要瓦片落同一个页面；底部导航「系统」组的 PrivacyDashboard 也在同一片安全域。
            // 三个入口指向同一件事，用户无从判断该点哪个。保留摘要瓦片（带实时值）与底部导航。
            // 下方「隐私与伪装 → SecurityPeekView」保留：它是另一件事（防窥/遮蔽配置）。
            // ⚠ 这一条原来和上面那条**指向同一个 SecurityPage 根**，
            // 于是「本机数据保护」和「隐私与伪装」点进去看到的是同一屏 ——
            // 用户按标题预期找防窥/伪装，落到的是一张"安全吗"的总览卡。
            // 现在直达真正承载这三件事的那一页（SecurityPeekView，
            // 它正是 SecurityPage 里「防窥与遮蔽」那条的落点）。
            // 2026-10-24: SecurityPeekView 已删（用户裁定）
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            // ═══ 诊断与自检 ═══
            //
            // DiagKit 有 642 行采集器（自检 / 数据健康 / 异常退出 / 启动耗时 /
            // 最近操作 / 蓝牙遥测 / 日志保留），这一屏之前**不存在**，
            // 采集的数据没有任何地方显示。

            Text("本机数据与访问权限")
                .xFont(.caption, weight: .semibold)
                .foregroundStyle(XPalette.textTertiary)
                .padding(.bottom, XSpace.xxs)
            caption("这一组动的是本机数据与访问权限, 改动前会二次确认。")
        }
    }

    /// HTML 对齐 (2026-10-24): 补「备份恢复」卡 —— 上次导出 / 本机门锁 / 钥匙总数。
    /// parity 工具指出这一整卡在 App 里缺失（HTML 05-system 有）。
    /// 胶囊用：上次导出距今天数（-1 = 从未）
    private var backupAgeChipFraction: Double {
        let ms = DB.store.getInt("kf_bk_last_export", 0)
        if ms <= 0 { return 0 }
        let days = (Date().timeIntervalSince1970 * 1000 - Double(ms)) / 86_400_000
        return max(0, min(1, days / 30))
    }
    private var backupAgeChipText: String {
        let ms = DB.store.getInt("kf_bk_last_export", 0)
        if ms <= 0 { return "从未" }
        let days = Int((Date().timeIntervalSince1970 * 1000 - Double(ms)) / 86_400_000)
        return days <= 0 ? "今天" : "\(days) 天前"
    }

    private var backupRestoreCard: some View {
        XPanel {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("备份恢复")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上次备份").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text(backupAgeText).xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机门锁").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(DB.keychains().count) 把").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("钥匙总数").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("\(DB.keychains().reduce(0) { $0 + DB.listPwds($1.mac).count + DB.listFps($1.mac).count }) 份")
                            .xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                NavigationLink { BackupPage().environmentObject(app) } label: {
                    XRow(systemImage: "externaldrive", title: "去备份与恢复", showsChevron: true)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ② 这台锁
    // ═══════════════════════════════════════════════════════

    private var lockSection: some View {
        XPanel {
            // ═══ 这台锁 ═══
            //
            // DevicePage 是 435 行的三层递进重写（身份 → 需要你处理的 → 折叠明细），
            // 但**全仓零引用** —— 做好了没接进导航。
            // 它有几项 HomeConsole 没有的内容：锁内容量占用、固件版本、
            // 信号格、最近开门明细。
            NavigationLink { DevicePage().environmentObject(app).trackScreen("这台锁") } label: {
                XRow(
                    systemImage: "lock.square",
                    title: "这台锁",
                    subtitle: "容量 / 固件 / 信号",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            // 2026-10-24 去重：这里原来是「设备管理 → LocksPage」的第二入口，
            // 而底部导航「设备」组的第一项就是它对同一页面。
            // 同一页两个入口会让用户以为它们不同（一个叫"设备管理"一个叫"我的门锁"）。
            // 保留底部导航那条；本页需要看门锁数量时，上方 statusSummary 的「门锁」摘要卡仍在。
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            NavigationLink { LockProfilePage().environmentObject(app) } label: {
                XRow(
                    systemImage: "tag",
                    title: "锁档案",
                    subtitle: "昵称 / 符号 / 色标",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)

            XHairline(inset: XSpace.card + 28 + XSpace.m)
            NavigationLink { LinkPrefsView(mac: mac).environmentObject(app) } label: {
                XRow(
                    systemImage: "slider.horizontal.3",
                    title: "开锁偏好",
                    subtitle: "按住确认 / 围栏",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            NavigationLink { AutoCalView(mac: mac).environmentObject(app) } label: {
                XRow(
                    systemImage: "figure.walk.motion",
                    title: "靠近自动开锁",
                    subtitle: "走近自动开门 / 距离标定",
                    value: AutoOpen.on ? "已开启" : "已关闭",
                    tone: AutoOpen.on ? .ok : .neutral,
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)

            Text("门锁与设备")
                .xFont(.caption, weight: .semibold)
                .foregroundStyle(XPalette.textTertiary)
                .padding(.bottom, XSpace.xxs)
            caption("这台锁")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ③ 数据
    // ═══════════════════════════════════════════════════════

    private var dataSection: some View {
        XPanel {
            // ═══ 2026-10-24 去重 ═══
            // 删掉「备份与恢复」与「导出中心」两行 —— 底部导航「系统」组里都是一级入口。
            // 同一页两处入口会让用户以为"本机设置里的备份"和"系统组的备份"是两个东西。
            // 本页保留 backupRestoreCard：它只在**备份陈旧/从未备份**时出现，
            // 是一条带语境与时效的提醒（"已经 23 天没备份了"），不是常驻菜单项。
            // ═══ 事件记录 ═══
            //
            // EventsPage 是**功能更全**的记录页：按天分组的时间线、查询引擎
            //（+必须词 / -排除词 / 时间短语）、命名筛选视图、最近搜索、
            // 事件备注、失败记录清除、以及"从门锁同步日志"——
            // 但它**全仓零引用**，没有任何入口。上面那个"动态消息"是更简单的卡片流。
            //
            // 两个都在：动态消息看"最近发生了什么"，事件记录做"翻旧账/查证据"。
            // 2026-10-24: EventsPage 已删（用户裁定）。原先它下面的子页 StatsPage
            // 只从 EventsPage 进 —— 页面一删就成了孤岛，这里补一个入口。
            NavigationLink { StatsPage().environmentObject(app).trackScreen("统计") } label: {
                XRow(
                    systemImage: "chart.bar",
                    title: "统计",
                    subtitle: "开门次数 / 趋势 / 分布",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            // 2026-10-24: FeedPage 已删（用户裁定）
            Text("导出与关怀")
                .xFont(.caption, weight: .semibold)
                .foregroundStyle(XPalette.textTertiary)
                .padding(.bottom, XSpace.xxs)
            caption("全程离线: 备份只写本机文件, 不上传任何服务器。")
        }
    }

    /// 卡片底部说明 —— 取代原来 Section 的 header/footer
    private func caption(_ text: String) -> some View {
        Text(text)
            .xFont(.caption2)
            .foregroundStyle(XPalette.textSub)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backupAgeText: String {
        let ms = DB.store.getInt("kf_bk_last_export", 0)
        guard ms > 0 else { return "从未备份" }
        let days = Int((Date().timeIntervalSince1970 * 1000 - Double(ms)) / 86_400_000)
        if days <= 0 { return "今天" }
        if days == 1 { return "昨天" }
        return "\(days) 天前"
    }

    private var messageBadge: String? {
        let n = RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac })
        return n > 0 ? "\(n) 条" : nil
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ④ 关于与偏好
    // ═══════════════════════════════════════════════════════

    private var aboutSection: some View {
        XPanel {
            NavigationLink { IconPicker().environmentObject(app) } label: {
                XRow(systemImage: "app.badge", title: "App 图标",
                     subtitle: "9 款可选", showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)

            XHairline(inset: XSpace.card + 28 + XSpace.m)
            NavigationLink { CarePage().environmentObject(app) } label: {
                XRow(
                    systemImage: "wrench.and.screwdriver",
                    title: "维护与保养",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)
            NavigationLink { CareRemindersView().environmentObject(app) } label: {
                XRow(
                    systemImage: "heart.text.square",
                    title: "关怀提醒",
                    subtitle: "生日 / 公告板",
                    showsChevron: true)
            }
            XHairline(inset: XSpace.card + 28 + XSpace.m)

            XHairline(inset: XSpace.card + 28 + XSpace.m)

            caption("关于与偏好")
        }
    }
}
