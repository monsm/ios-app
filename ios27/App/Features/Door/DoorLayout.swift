// DoorLayout.swift —— 设备页的版面顺序与模块显隐（原 DeviceHomeView.swift:77,354-460 的 moduleOrderSheet）。
//
// 三个可排序槽（状态卡 / 快捷格 / 最近开门）是**版面结构**，与 DevModuleStore 的模块显隐分开：
//   · 槽位顺序：kf_dev_order（CSV，白名单过滤 + 去重；认不出的 id 丢掉，不把用户设置打空）
//   · 模块显隐：Engine/DevModules.swift 的 DevModuleStore（kf_dev_hidden）
// 恢复默认 = 删这两个键 + QuickPool 回到默认六格。
import SwiftUI

enum DevSlot: String, CaseIterable, Identifiable {
    case status
    case quick
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "状态卡"
        case .quick: return "快捷格"
        case .recent: return "最近开门"
        }
    }

    var note: String {
        switch self {
        case .status: return "电量主环 / 读数 / 今日面积图"
        case .quick: return "10 选 N 的快捷操作格"
        case .recent: return "最近 N 条开门（条数在外观里改）"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "gauge.with.dots.needle.50percent"
        case .quick: return "square.grid.2x2"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

enum DevLayout {
    static let orderKey = "kf_dev_order"

    /// 读顺序：白名单过滤，缺的槽补在末尾（升级后新槽不会消失）。
    static var order: [DevSlot] {
        let raw = DB.store.get([String].self, orderKey) ?? []
        var seen = Set<DevSlot>()
        var out: [DevSlot] = []
        for item in raw {
            guard let slot = DevSlot(rawValue: item), !seen.contains(slot) else { continue }
            seen.insert(slot)
            out.append(slot)
        }
        for slot in DevSlot.allCases where !seen.contains(slot) { out.append(slot) }
        return out
    }

    static func setOrder(_ slots: [DevSlot]) {
        let clean = DevSlot.allCases.filter { slots.contains($0) }
        if clean == DevSlot.allCases { DB.store.remove(orderKey) }
        else { DB.store.set(orderKey, clean.map(\.rawValue)) }
    }

    static func move(_ slot: DevSlot, by delta: Int) {
        var list = order
        guard let i = list.firstIndex(of: slot) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        setOrder(list)
    }

    static func reset() {
        DB.store.remove(orderKey)
        DevModuleStore.reset()
        QuickPool.setSelected(QuickPool.defaultIds)
    }
}
