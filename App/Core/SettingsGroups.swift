// 设置页五组分区 (乱源治理第 4 批)
//
// 乱源: 设置页把 17 个 Section、约 37 个一级入口平铺在一屏 —— 找一个开关要划过整页。
// 做法: 顶部一排筛选片 (全部 + 五组)，每个 Section 只多一行 `if group == nil || group == .x`。
//       **不改任何 section 的内部、不挪任何入口、不新建页面** —— 分组只是"这一屏先给你看哪几节",
//       页内搜索 (§27) 照常在片子上方工作, 两条路径互不影响。
//
// 归属判据 (按"用户此刻想干的事", 不是按代码里的实现归属):
//   · 开门日常 —— 锁本身: 门锁信息 / 设备管理 / 开锁行为 / 自动开门 / 提醒与告警音
//   · 凭证与成员 —— 谁能开门: 家人与钥匙那一大节
//   · 数据与安全 —— 数据与设备维护: 安全 / 工具(总览·网关·固件·备份) / 本机数据保护 / 演练与演示
//   · 外观与辅助 —— 看起来与用起来: 时间显示 / 无障碍 / 外观
//   · 帮助与关于 —— 读的东西: 纪念与成就 / 帮助 / 关于
// 一个 Section 只进一组: 允许它同时出现在两组就等于没收敛 (工具节里"备份与恢复"和"智能网关"
// 确实分属两件事, 但把一节拆成两处会让页内搜索的命中映射出现两个落点 —— 那是更大的乱)。
import SwiftUI

enum SettingsGroup: String, CaseIterable, Identifiable {
    case daily       // 开门日常
    case keys        // 凭证与成员
    case data        // 数据与安全
    case look        // 外观与辅助
    case help        // 帮助与关于

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "开门日常"
        case .keys: return "凭证与成员"
        case .data: return "数据与安全"
        case .look: return "外观与辅助"
        case .help: return "帮助与关于"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "lock.open"
        case .keys: return "key.horizontal"
        case .data: return "lock.shield"
        case .look: return "paintbrush"
        case .help: return "questionmark.circle"
        }
    }
}

/// 这一节现在该不该出现。`nil` = 全部 (与加这一批之前的画面逐字一致 —— 默认态不许变)。
func settingsSectionShown(_ group: SettingsGroup?, _ mine: SettingsGroup) -> Bool {
    group == nil || group == mine
}

