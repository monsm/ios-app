// 共享条带卡 (本包落点迁移) — 288 电量总览条带。
// 288 拍板落点 = 设备管理页头 (DeviceManageView), 全部锁总览页 (LockOverviewView) 继续挂同一组件;
// 业主口径「复用 batteryStripCard, 不许再画第二份」⇒ 全仓仅此一份实现, 两页各自实例化。
// 数据口径原样搬自 LockOverviewView.swift:80-130 原 private var batteryStripCard:
//   · 展示统一取采样最新值 (BatteryCare.displayPct), 快照仅作兜底 (包4);
//   · 低电靠左 = pct 升序 (1041 同一条), 未知电量整体垫底, 同 pct 按锁名定序;
//   · 每锁一格, 判据 = LockStats.usage() 出的每把锁 (u.mac 取采样, u.power 作快照兜底)。
// 依赖参数化: 原属性读 LockOverviewView 的 @State usages ([LockUsage]), 现改构造参数 ——
// 两页各自调同一口径的 LockStats.usage() 传入; 卡内排序只看 pct/name, 与传入次序无关,
// 所以同数据必同渲染, 页头那份与总览那份可逐格对照。
import SwiftUI

struct BatteryStripCard: View {
    let usages: [LockUsage]

    var body: some View {
        stripCard
    }

    // ---------- 288 电量总览条带 (低电靠左 = 1041 电量升序) + 45 趋势积累说明 ----------
    private var stripCard: some View {
        // 包4: 展示统一取采样最新值 (BatteryCare.displayPct), 快照仅作兜底
        let resolved: [(u: LockUsage, pct: Int)] = usages.map { u in
            (u, BatteryCare.displayPct(u.mac, snapshot: u.power))
        }
        let sorted = resolved.sorted { a, b in
            let aUnknown = a.pct < 0, bUnknown = b.pct < 0
            if aUnknown != bUnknown { return !aUnknown }
            if a.pct != b.pct { return a.pct < b.pct }
            return a.u.name < b.u.name
        }
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle(text: "电量", count: usages.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                            let u = item.u
                            let t = BatteryCare.tier(item.pct)
                            VStack(spacing: DS.Space.xxs) {
                                Image(systemName: t.icon)
                                    .font(.system(size: DS.Icon.lg, weight: .medium))
                                    .foregroundStyle(t.tone.color)
                                    .accessibilityHidden(true)
                                // 写法走 BatteryCare.faceText —— 这条 ">80% / --" 的规则设备页那侧同一份,
                                // 两处各写各的早晚漂 (2026-10-15 走查)。无障碍那行仍念精确百分比, 那是有意的:
                                // 屏上省略是为"80 以上都算充足"这个判据服务, 念出来时给准数更有用。
                                Text(BatteryCare.faceText(item.pct))
                                    .vkFont(.caption2, weight: .medium)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.Palette.text)
                                Text(u.name)
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, DS.Space.xs)
                            .padding(.vertical, DS.Space.xs)
                            .frame(width: 68)
                            .variantPlate(DS.Palette.surfaceAlt, .tile)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(u.name) 电量 \(item.pct < 0 ? "未知" : "\(item.pct)%")")
                        }
                    }
                }
                Text("趋势曲线积累中 — 每次连接门锁自动记录一个电量采样点, 存满约一周后可看走势; 换电池指引见锁详情。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
