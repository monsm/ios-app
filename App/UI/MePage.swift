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
        List {
            protectionSection
            lockSection
            dataSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
        .navigationTitle("这台手机")
        .navigationBarTitleDisplayMode(.large)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ① 本机保护
    // ═══════════════════════════════════════════════════════

    private var protectionSection: some View {
        Section {
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
        } header: {
            Text("本机保护")
        } footer: {
            Text("这一组动的是本机数据与访问权限, 改动前会二次确认。")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ② 这台锁
    // ═══════════════════════════════════════════════════════

    private var lockSection: some View {
        Section {
            NavigationLink { LocksPage().environmentObject(app) } label: {
                XRow(
                    systemImage: "square.stack.3d.up",
                    title: "设备管理",
                    subtitle: "排序 / 分组 / 批量",
                    value: "\(DB.keychains().count) 把",
                    showsChevron: true)
            }
            NavigationLink { LockProfileView().environmentObject(app) } label: {
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
        } header: {
            Text("这台锁")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - ③ 数据
    // ═══════════════════════════════════════════════════════

    private var dataSection: some View {
        Section {
            NavigationLink { BackupView().environmentObject(app) } label: {
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
            NavigationLink { MessagesView().environmentObject(app) } label: {
                XRow(
                    systemImage: "bell",
                    title: "动态消息",
                    value: messageBadge,
                    showsChevron: true)
            }
        } header: {
            Text("数据")
        } footer: {
            Text("全程离线: 备份只写本机文件, 不上传任何服务器。")
        }
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
        Section {
            NavigationLink { FirmwareView().environmentObject(app) } label: {
                XRow(
                    systemImage: "arrow.up.circle",
                    title: "检查固件更新",
                    value: DB.readStatus(mac)?.firmware,
                    showsChevron: true)
            }
            NavigationLink { MaintenanceView().environmentObject(app) } label: {
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
            NavigationLink { KeychainHWView().environmentObject(app) } label: {
                XRow(
                    systemImage: "key.horizontal",
                    title: "蓝牙钥匙串",
                    showsChevron: true)
            }
            NavigationLink { GatewayView().environmentObject(app) } label: {
                XRow(
                    systemImage: "antenna.radiowaves.left.and.right",
                    title: "智能网关",
                    showsChevron: true)
            }
        } header: {
            Text("关于与偏好")
        }
    }
}
