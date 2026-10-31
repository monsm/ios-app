// Ledger.swift —— 台账行与时间轴。
//
// 仪器台账的语法：等宽时刻在左（对齐成列）、事件在中间、状态点在右。
// 行内信息点不超过 3 个；不给每行套圆角卡（那是模板脸）。
import SwiftUI

/// 一条台账记录（来自锁内 cmd16 日志或手机侧事件）。
struct LedgerEntry: Identifiable, Hashable {
    let id: String
    /// 发生时刻（毫秒 epoch）。
    let at: Int64
    /// 事件短语（「指纹开锁」「密码错误」「门未关」）。
    let event: String
    /// 归属人（可空）。
    let owner: String?
    /// 语义色。
    let tone: Tone
    /// 详情（展开后可见）。
    var detail: String? = nil
}

extension LedgerEntry {
    /// 演示/预览用的种子。真实现由 Engine 的 Store / StatusParser 提供，
    /// 这里只保证「空态与有数据态都能被渲染出来」，不冒充真实记录。
    static let sample: [LedgerEntry] = {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let h: Int64 = 3600_000
        return [
            LedgerEntry(id: "s1", at: now - 3 * h, event: "指纹开锁", owner: "妈妈", tone: .ok),
            LedgerEntry(id: "s2", at: now - 5 * h, event: "密码开锁", owner: "我", tone: .ok),
            LedgerEntry(id: "s3", at: now - 8 * h, event: "密码错误 ×2", owner: "未识别", tone: .attention),
            LedgerEntry(id: "s4", at: now - 12 * h, event: "临时码开锁", owner: "保洁 周三", tone: .ok),
            LedgerEntry(id: "s5", at: now - 26 * h, event: "门未关严", owner: nil, tone: .critical),
            LedgerEntry(id: "s6", at: now - 29 * h, event: "手机钥匙开锁", owner: "我", tone: .ok),
        ]
    }()
}

/// 台账行。时刻等宽对齐成列，是这个设计最容易认出来的地方。
struct LedgerRow: View {
    let entry: LedgerEntry
    var showDay: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.S.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeFormat.clock(entry.at))
                    .font(T.F.stamp)
                    .foregroundStyle(Ink.ink)
                    .monospacedDigit()
                if showDay {
                    Text(TimeFormat.dayShort(entry.at))
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .monospacedDigit()
                }
            }
            .frame(width: showDay ? 58 : 48, alignment: .leading)

            VStack(alignment: .leading, spacing: T.S.xxs) {
                Text(entry.event)
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
                if let owner = entry.owner, !owner.isEmpty {
                    Text(owner)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkSub)
                }
            }

            Spacer(minLength: T.S.s)

            StateDot(tone: entry.tone, word: entry.event)
        }
        .frame(minHeight: T.Hit.min + T.S.s)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(TimeFormat.clock(entry.at)) \(entry.event)" +
            (entry.owner.map { "，\($0)" } ?? "")
        )
    }
}

/// 台账分组：按自然日。组头是「今天 / 昨天 / MM-DD」+ 条数读数。
struct LedgerDayHeader: View {
    let dayKey: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
            Text(TimeFormat.dayTitle(dayKey))
                .font(T.F.section)
                .foregroundStyle(Ink.ink)
            Spacer(minLength: T.S.s)
            Reading(value: "\(count)", unit: "条", size: 13, weight: .regular, tint: Ink.inkFaint, animated: false)
        }
        .padding(.horizontal, T.S.gutter)
        .padding(.top, T.S.l)
        .padding(.bottom, T.S.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 台账容器：把条目按自然日分组的纯逻辑（可测）。
enum LedgerGrouping {
    static func group(_ entries: [LedgerEntry]) -> [(dayKey: String, items: [LedgerEntry])] {
        let cal = TimeFormat.calendar
        var buckets: [String: [LedgerEntry]] = [:]
        for e in entries {
            let key = TimeFormat.dayKey(e.at)
            buckets[key, default: []].append(e)
        }
        return buckets
            .map { (dayKey: $0.key, items: $0.value.sorted { $0.at > $1.at }) }
            .sorted { $0.dayKey > $1.dayKey }
    }
}
