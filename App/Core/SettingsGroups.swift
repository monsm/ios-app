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

/// 顶部筛选片。选中态写进调用方的 @State，这里只管画与切。
struct SettingsGroupChips: View {
    @Binding var selection: SettingsGroup?

    var body: some View {
        // 2026-10-15 走查: 原为 `ScrollView(.horizontal, showsIndicators: false)` —— 六枚片
        // (全部/开门日常/凭证与成员/数据与安全/外观与辅助/帮助与关于) 总宽约 656pt, 而这一行的
        // 可用宽只有 ~361pt, 于是后两枚永远在滚动区外, 连"还能滚"都不提示。这与本仓自己在
        // App 图标选择器上写下的原则相悖 (SettingsView 里那条: 横向 ScrollView "会把后几款
        // 藏在滚动区外, 用户不知道自己有九款可选")。改用 FlowLayout 按宽度换行铺开:
        // 六枚全在屏上, 片形 (贴字胶囊) 一点没变。
        FlowLayout(spacing: DS.Space.s) {
            chip(nil, "全部", "square.grid.2x2")
            ForEach(SettingsGroup.allCases) { g in chip(g, g.title, g.icon) }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置分区筛选，当前\(selection?.title ?? "全部")")
    }

    @ViewBuilder
    private func chip(_ g: SettingsGroup?, _ title: String, _ icon: String) -> some View {
        let on = selection == g
        Button {
            DS.Haptics.tick.impactOccurred()
            withAnimation(DS.Motion.quick) { selection = g }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: on ? "checkmark.circle.fill" : icon)
                    .font(.system(size: DS.Icon.xs))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(on ? .semibold : .regular))
            }
            .foregroundStyle(on ? DS.Palette.accentText : DS.Palette.text)
            .padding(.horizontal, DS.Space.m)
            .frame(minHeight: DS.Hit.min)
            .background(on ? DS.Palette.accent.opacity(0.14) : DS.Palette.surfaceAlt, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
