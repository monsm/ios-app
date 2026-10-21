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

    var body: some View {
        // M5 重做: List + Section → ScrollView + XPanel 卡片流
        //
        // 五个 Section 的内容一行没动（都是 XRow / summaryTile），
        // 只把外壳换成 XPanel，header/footer 转成卡片底部 caption。
        ScrollView {
            VStack(spacing: XSpace.l) {
                statusSummary
                protectionSection
                lockSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.top, XSpace.s)
            .padding(.bottom, XSpace.xxl)
        }
        .background(XPalette.canvas)
        .navigationTitle("这台手机")
        .navigationBarTitleDisplayMode(.large)
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
    private var statusSummary: some View {
        let locked = DB.store.getBool("kf_applock")
        let alarmN = RecordSearch.unhandledAlarmCount(macs: DB.keychains().map { $0.mac })
        let bkMs = DB.store.getInt("kf_bk_last_export", 0)
        let bkDays = bkMs > 0
            ? Int((Date().timeIntervalSince1970 * 1000 - Double(bkMs)) / 86_400_000)
            : -1
        let locks = DB.keychains().count

        return XPanel {
            HStack(spacing: XSpace.s) {
                summaryTile(
                    icon: locked ? "lock.shield.fill" : "lock.open",
                    value: locked ? "已锁" : "未锁",
                    label: "应用锁",
                    tone: locked ? XPalette.ok : XPalette.warn)
                summaryTile(
                    icon: alarmN > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    value: alarmN > 0 ? "\(alarmN)" : "0",
                    label: "待处理告警",
                    tone: alarmN > 0 ? XPalette.warn : XPalette.ok)
                summaryTile(
                    icon: bkDays < 0 ? "externaldrive.badge.questionmark" : "externaldrive.fill",
                    value: bkDays < 0 ? "从未" : (bkDays <= 0 ? "今天" : "\(bkDays)天"),
                    label: "上次备份",
                    tone: bkDays < 0 ? XPalette.warn : (bkDays > 14 ? XPalette.warn : XPalette.ok))
                summaryTile(
                    icon: "square.stack.3d.up.fill",
                    value: "\(locks)",
                    label: "门锁",
                    tone: locks > 0 ? XPalette.accent : XPalette.textTertiary)
            }
            .padding(.vertical, XSpace.xs)
        }
    }

    /// 一个大数字指标 —— 数值在前，标签在后
    ///
    /// 与原来相比（M5 形态改造）:
    ///   · 去掉 34pt 图标圆 —— 它占了近一半高度却只传达"这是哪一项"
    ///   · 数值从 subheadline 提到 title2 —— 一眼看到的是数，不是装饰
    ///   · 高度统一 76pt，四张卡并排不会高低不齐
    private func summaryTile(icon: String, value: String, label: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .xFont(.title2, weight: .bold)
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .xFont(.caption2)
            .foregroundStyle(XPalette.textTertiary)
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
            NavigationLink { SecurityPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "lock.shield",
                    title: "本机数据保护",
                    subtitle: "应用锁 / 审计 / 销毁",
                    value: DB.store.getBool("kf_applock") ? "已开启" : "未开启",
                    tone: DB.store.getBool("kf_applock") ? .ok : .warn,
                    showsChevron: true)
            }
            NavigationLink { SecurityPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "eye.slash",
                    title: "隐私与伪装",
                    subtitle: "偷窥模式 / 伪装 / 访客通道",
                    showsChevron: true)
            }
            caption("这一组动的是本机数据与访问权限, 改动前会二次确认。")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ② 这台锁
    // ═══════════════════════════════════════════════════════

    private var lockSection: some View {
        XPanel {
            NavigationLink { LocksPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "square.stack.3d.up",
                    title: "设备管理",
                    subtitle: "排序 / 分组 / 批量",
                    value: "\(DB.keychains().count) 把",
                    showsChevron: true)
            }
            NavigationLink { LockProfilePage().environmentObject(app) } label: {
                XRow(
                    systemImage: "tag",
                    title: "锁档案",
                    subtitle: "昵称 / 符号 / 色标",
                    showsChevron: true)
            }
            NavigationLink { SyncTimeView().environmentObject(app) } label: {
                XRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "校准门锁时间",
                    showsChevron: true)
            }
            NavigationLink { LinkPrefsView(mac: mac).environmentObject(app) } label: {
                XRow(
                    systemImage: "slider.horizontal.3",
                    title: "开锁偏好",
                    subtitle: "按住确认 / 围栏 / 提示音",
                    showsChevron: true)
            }
            NavigationLink { AutoCalView(mac: mac).environmentObject(app) } label: {
                XRow(
                    systemImage: "figure.walk.motion",
                    title: "靠近自动开锁",
                    subtitle: "走近自动开门 / 距离标定",
                    value: AutoOpen.on ? "已开启" : "已关闭",
                    tone: AutoOpen.on ? .ok : .neutral,
                    showsChevron: true)
            }
            NavigationLink { SafemodeIntroView().environmentObject(app) } label: {
                XRow(
                    systemImage: "shield.lefthalf.filled",
                    title: "门锁安全模式",
                    showsChevron: true)
            }
            caption("这台锁")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ③ 数据
    // ═══════════════════════════════════════════════════════

    private var dataSection: some View {
        XPanel {
            NavigationLink { BackupPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "externaldrive",
                    title: "备份与恢复",
                    subtitle: "全量导出 / 导入",
                    value: backupAgeText,
                    showsChevron: true)
            }
            NavigationLink { ExportCenterView(mac: mac).environmentObject(app) } label: {
                XRow(
                    systemImage: "square.and.arrow.up",
                    title: "导出中心",
                    subtitle: "CSV / 报告",
                    showsChevron: true)
            }
            // ═══ 事件记录 ═══
            //
            // EventsPage 是**功能更全**的记录页：按天分组的时间线、查询引擎
            //（+必须词 / -排除词 / 时间短语）、命名筛选视图、最近搜索、
            // 事件备注、失败记录清除、以及"从门锁同步日志"——
            // 但它**全仓零引用**，没有任何入口。上面那个"动态消息"是更简单的卡片流。
            //
            // 两个都在：动态消息看"最近发生了什么"，事件记录做"翻旧账/查证据"。
            NavigationLink { EventsPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "list.bullet.rectangle",
                    title: "事件记录",
                    subtitle: "按天浏览 · 搜索筛选 · 从门锁同步",
                    showsChevron: true)
            }
            NavigationLink { FeedPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "bell",
                    title: "动态消息",
                    value: messageBadge,
                    showsChevron: true)
            }
            caption("全程离线: 备份只写本机文件, 不上传任何服务器。")
        }
    }

    /// 卡片底部说明 —— 取代原来 Section 的 header/footer
    private func caption(_ text: String) -> some View {
        Text(text)
            .xFont(.caption2)
            .foregroundStyle(XPalette.textTertiary)
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
                     subtitle: "锁环 / 钥匙 / 盾牌 等 9 款", showsChevron: true)
            }
            NavigationLink { FirmwarePage().environmentObject(app) } label: {
                XRow(
                    systemImage: "arrow.up.circle",
                    title: "检查固件更新",
                    value: DB.readStatus(mac)?.firmware,
                    showsChevron: true)
            }
            NavigationLink { CarePage().environmentObject(app) } label: {
                XRow(
                    systemImage: "wrench.and.screwdriver",
                    title: "维护与保养",
                    showsChevron: true)
            }
            NavigationLink { CareRemindersView().environmentObject(app) } label: {
                XRow(
                    systemImage: "heart.text.square",
                    title: "关怀提醒",
                    subtitle: "生日 / 公告板",
                    showsChevron: true)
            }
            NavigationLink { DonglesPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "key.horizontal",
                    title: "蓝牙钥匙串",
                    showsChevron: true)
            }
            NavigationLink { GatewayPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "antenna.radiowaves.left.and.right",
                    title: "智能网关",
                    showsChevron: true)
            }
            caption("关于与偏好")
        }
    }
}
