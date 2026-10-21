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

