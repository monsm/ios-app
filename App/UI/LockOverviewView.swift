// 全部锁总览与对比 (包3) — 768 待维护清单 / 776 活跃度条形榜 / 778 告警率对比列 /
// 779 成员×锁交叉矩阵 / 784 固件版本对照表 / 773 凭证容量水位 / 787 对比结论一句话 / 769 绑定时间标注。
// 数据源全部是既有本地表 (日志缓存/台账/快照/钥匙串), 统计逻辑在 App/Core/LockStats.swift。
import SwiftUI

/// 768/778 下钻目标: 用 Identifiable 包一层 mac 给 .sheet(item:) 用
private struct AlarmTarget: Identifiable {
    let mac: String
    var id: String { mac }
}

struct LockOverviewView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var usages: [LockUsage] = []
    @State private var loaded = false
    // 768/778: 待维护行与活跃度行都在本页本地 sheet 里弹单锁告警流 —— 不走跨 Tab 跳转,
    // 关掉 sheet 就回到总览, 不丢滚动位置也不挪当前锁。
    @State private var alarmTarget: AlarmTarget? = nil
    /// 778 偏高阈值: 上浮排序、染色、标签共用一个数 (散写三处迟早漂)
    private static let alarmHighCut = 0.2

    var body: some View { vkBody }
    var vkBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: XSpace.m) {
                    // 2026-10-15 走查: `loaded` 这一位在 .task 里置真、**全文件没有任何一处读它** ⇒
                    // 有锁的用户首帧拿到的是 `usages = []`，于是先闪一屏"还没有门锁 / 添加第二把门锁后…"，
                    // 下一拍数据到了再换成对比卡。空态要分"还没读"与"真的没有"两档。
                    if !loaded {
                        ProgressView().padding(XSpace.xl)
                    } else if usages.isEmpty {
                        Card {
                            XEmptyState(systemImage: "lock.square.stack",
                                       title: "还没有门锁",
                                       message: "添加第二把门锁后, 这里会给出活跃度、告警率与固件版本的多锁对比。")
                        }
                    } else {
                        summaryCard.staggered(0)        // 787
                        // 288 电量条带本包拍板落点 = 设备管理页头; 总览页这一格保留 (删格=砍现有功能)。
                        // 两页共用同一份 BatteryStripCard (App/UI/DeviceStripCard.swift), 全仓仅此一个实现。
                        BatteryStripCard(usages: usages).staggered(1)   // 288/1041/45 (包4)
                        maintenanceCard.staggered(2)    // 768
                        signalCard.staggered(3)         // 71 列表信号预览 (包2)
                        capacityCard.staggered(5)       // 773
                        firmwareCard.staggered(6)       // 784 + 769
                    }
                }
                .padding(.vertical, XSpace.m)
            }
            .xScreen()
            .navigationTitle("全部锁总览")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .task {
                usages = LockStats.usage()
                loaded = true
            }
            .sheet(item: $alarmTarget) { t in
                AlarmCenterView(lockMac: t.mac)
            }
        }
    }

    // ---------- 787 对比结论一句话 ----------
    private var summaryCard: some View {
        Card {
            HStack(alignment: .top, spacing: XSpace.s) {
                Image(systemName: "text.quote")
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(XPalette.accentText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(LockStats.summary(usages))
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // ---------- 288 电量总览条带 ----------
    // 原 private var batteryStripCard (本文件:80-130) 本包整体迁入 BatteryStripCard
    // (App/UI/DeviceStripCard.swift): 排序 (低电靠左/未知垫底/同 pct 按名)、每锁一格判据、
    // displayPct 采样优先快照兜底、趋势脚注, 一行口径原样搬; usages 由私有状态改造成构造参数,
    // 本页 .task 里 LockStats.usage() 的结果原样传入, 数据口径与迁移前一致。

    // ---------- 768 待维护锁清单 ----------
    @ViewBuilder
    private var maintenanceCard: some View {
        let list = LockStats.maintenance(usages)
        if !list.isEmpty {
            Card(tint: .warn) {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    SectionTitle(text: "待维护", count: list.count)
                    ForEach(list) { item in
                        Button {
                            alarmTarget = AlarmTarget(mac: item.usage.mac)   // 768: 直达该锁告警流
                        } label: {
                            HStack(spacing: XSpace.s) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: XIcon.sm, weight: .semibold))
                                    .foregroundStyle(XPalette.warn)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: XSpace.xxs) {
                                    Text(item.usage.name)
                                        .xFont(.subheadline)
                                        .foregroundStyle(XPalette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(item.reasons.joined(separator: " · "))
                                        .xFont(.caption)
                                        .foregroundStyle(XPalette.warn)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: XIcon.xs, weight: .semibold))
                                    .foregroundStyle(XPalette.textSub)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("\(item.usage.name) 待维护: \(item.reasons.joined(separator: ", ")), 点按下钻该锁告警流")   // 768 待维护
                    }
                }
            }
        }
    }


    // ---------- 71 列表信号预览 (包2): 每行右侧迷你信号格, 切换前先看哪把锁在范围内 ----------
    // RSSI 来自各锁最近一次扫描 (kf_linkrssi_), 未扫到 = 无信号格 (不虚构);
    // 540 第三处角标已舍弃, 本卡是列表行的唯一展示位。
    // 2026-10-13 run 60: 原写 `if … { return Card {…} }; return Card {…}` —— 两个 return 的
    // `Card<…>` 泛型内容不同, 而 `some View` 要求所有 return 的底层类型一致 ⇒
    // "function declares an opaque return type 'some View', but the return statements in its body
    //  do not have matching underlying types"。改成 @ViewBuilder + if/else 单表达式,
    // 由构建器把两支包成 _ConditionalContent, 底层类型唯一。
    @ViewBuilder
    private var signalCard: some View {
        let withSignal = usages.filter { LinkSense.rssiFor($0.mac) != nil }
        if withSignal.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    SectionTitle(text: "信号", count: usages.count)
                    Text("还没扫到任何锁的蓝牙广播 — 到设备页点一次刷新或靠近门锁, 信号格即现。")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: XSpace.s) {
                    SectionTitle(text: "信号预览", count: withSignal.count)
                    ForEach(withSignal) { u in
                        let lvl = LinkSense.rssiLevel(LinkSense.rssiFor(u.mac))
                        HStack(spacing: XSpace.s) {
                            Text(u.name)
                                .xFont(.subheadline)
                                .foregroundStyle(XPalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Text(LinkSense.rssiLabel(lvl))
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                            RSSIBars(level: lvl, tint: lvl >= 3 ? XPalette.ok : XPalette.warn)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(u.name) 信号" + LinkSense.rssiLabel(lvl))
                    }
                    Text("信号格来自最近一次广播扫描 · 切换前先看看哪把锁在范围内。")   // 71 信号格来自最近一次广
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }


    // ---------- 773 凭证容量水位 ----------
    private var capacityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: XSpace.s) {
                SectionTitle(text: "凭证容量", count: usages.count)
                ForEach(usages) { u in
                    let util = max(utilization(u), 0)
                    VStack(alignment: .leading, spacing: XSpace.xxs) {
                        HStack(spacing: XSpace.s) {
                            Text(u.name)
                                .xFont(.caption)
                                .foregroundStyle(XPalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: XSpace.s)
                            Text(capText(u))
                                .xFont(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(util >= 0.85 ? XPalette.warn : XPalette.textSub)
                        }
                        if hasKnownCap(u) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(XPalette.surfaceAlt)
                                    Capsule()
                                        .fill(util >= 0.85 ? XPalette.warn : XPalette.accent)
                                        .frame(width: geo.size.width * CGFloat(min(util, 1)))
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        }
                        if util >= 0.85, hasKnownCap(u) {
                            Text("接近满载, 建议清理过期凭证")
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.warn)
                        }
                    }
                    .padding(.vertical, XSpace.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.name) \(capText(u))")
                }
            }
        }
    }
    private func hasKnownCap(_ u: LockUsage) -> Bool { u.pwdCap > 0 || u.fpCap > 0 }
    /// 综合利用率: 密码/指纹取两者已用比例的最大值; 容量未知 → 台账计数对典型上限 (密码 10/指纹 20) 估
    private func utilization(_ u: LockUsage) -> Double {
        let pwdRatio = u.pwdCap > 0 ? Double(u.pwdUsed) / Double(u.pwdCap)
                                    : Double(max(u.pwdUsed, 0)) / 10.0
        let fpRatio = u.fpCap > 0 ? Double(u.fpUsed) / Double(u.fpCap)
                                  : Double(max(u.fpUsed, 0)) / 20.0
        return max(pwdRatio, fpRatio)
    }
    private func capText(_ u: LockUsage) -> String {
        // 2026-10-15 走查: 容量没读到时 (pwdCap/fpCap ≤ 0) 印的是**本机台账**的条数 —— 773 那条兜底。
        // 屏上却看不出这一点: "密码 0 条"会被读成"锁里没有密码", 而真实情况可能是"这台锁的容量没读回来、
        // 台账里也没记过"。给一个来源后缀, 让这一格说的是它真正代表的东西。
        let pwd = u.pwdCap > 0 ? "\(u.pwdUsed)/\(u.pwdCap)" : "\(u.pwdUsed) 条"
        let fp = u.fpCap > 0 ? "\(u.fpUsed)/\(u.fpCap)" : "\(u.fpUsed) 枚"
        return "密码 \(pwd) · 指纹 \(fp)" + (hasKnownCap(u) ? "" : " · 按台账")
    }

    // ---------- 784 固件版本对照表 (+769 绑定时间标注) ----------
    private var firmwareCard: some View {
        let lag = LockStats.fwLag(usages)
        return Card {
            VStack(alignment: .leading, spacing: XSpace.s) {
                SectionTitle(text: "固件对照", count: usages.count)
                ForEach(usages) { u in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: "memorychip")
                            .font(.system(size: XIcon.sm))
                            .foregroundStyle(lag.lagging.contains(u.mac) ? XPalette.warn : XPalette.textSub)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: XSpace.xxs) {
                            Text(u.name)
                                .xFont(.caption)
                                .foregroundStyle(XPalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            // 769 绑定时间标注
                            Text(boundText(u))
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                        }
                        Spacer(minLength: XSpace.s)
                        Text(u.fw.isEmpty ? "未读到" : "v" + u.fw)
                            .xFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(lag.lagging.contains(u.mac) ? XPalette.warn : XPalette.text)
                        if lag.lagging.contains(u.mac) {
                            XStatusPill(text: "旧版本", tone: .warn, systemImage: "arrow.down.circle")
                        } else if PidMap.canDeviceUpgrade(pidOf(u.mac)) {
                            XStatusPill(text: "可本地升级", tone: .ok, systemImage: "arrow.up.circle")
                        }
                    }
                    .frame(minHeight: XHit.min)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(u.name), 固件 \(u.fw.isEmpty ? "未读到" : u.fw)\(lag.lagging.contains(u.mac) ? ", 落后于本机最新" : "")")
                }
            }
        }
    }
    /// 769 口径收在 LockArchive.boundLabel 一处 (设备管理行与总览固件卡同源, 免两处漂)
    private func boundText(_ u: LockUsage) -> String { LockArchive.boundLabel(u.pairedAt) }
    private func pidOf(_ mac: String) -> Int { app.devices.first { $0.mac == mac }?.pid ?? 0 }
}
