// WeekBars.swift —— 近 7 天开门柱状图（D7）。
//
// 家维度挂在洞察页、成员维度挂在成员详情。只读：柱子不高亮、不可点 ——
// 它的职责是"这一周谁常来"，点开某一天是记录页自己的事。
import SwiftUI

struct WeekBars: View {
    struct Day: Identifiable {
        let key: String
        let label: String
        let count: Int
        var id: String { key }
    }

    let days: [Day]

    /// 柱子满高。零也有 3pt 的"底座"，让 0 与缺失长得不一样。
    private let maxHeight: CGFloat = 72
    private var peak: Int { max(days.map(\.count).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { d in
                VStack(spacing: 6) {
                    Text(d.count > 0 ? "\(d.count)" : " ")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink2)
                        .monospacedDigit()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(d.count > 0 ? T.C.brass : T.C.hair)
                        .frame(height: d.count > 0 ? max(6, maxHeight * CGFloat(d.count) / CGFloat(peak)) : 3)
                    Text(d.label)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 由事件流建出最近 7 天（含今天，旧→新）。`isOpen` 只数真正的开门，
    /// 校时/状态广播这类"没有人在门口"的记录不算。
    @MainActor
    static func build(events: [EventItem], memberID: String? = nil) -> [Day] {
        let cal = WeekCal.gregorian
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        var buckets: [String: Int] = [:]
        for e in events where e.isOpen && e.hasTime {
            if let memberID, e.whoID != memberID { continue }
            buckets[When.dayKey(e.time), default: 0] += 1
        }
        var out: [Day] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let key = When.dayKey(When.epochSeconds(day))
            // Calendar 的 weekday：1=周日…7=周六，直接映射到 "日一二三四五六"。
            let wd = cal.component(.weekday, from: day)
            let label = offset == 0 ? "今" : weekdays[wd - 1]
            out.append(Day(key: key, label: label, count: buckets[key] ?? 0))
        }
        return out
    }
}
