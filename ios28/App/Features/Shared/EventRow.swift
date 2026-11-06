// EventRow.swift —— 时间线行。三通道：形状（点）、颜色（黄铜/朱红/灰）、文字。
import SwiftUI

@MainActor
struct EventRow: View {
    var event: EventItem
    var showLock: Bool = false

    private var dotColor: Color {
        if event.isAlarm { return T.C.danger }
        if event.isOpen { return T.C.brass }
        return T.C.ink4
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.isAlarm ? T.C.danger : T.C.canvas)
                .overlay {
                    Circle().strokeBorder(dotColor, lineWidth: 1.5)
                }
                .frame(width: 9, height: 9)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.typeName)
                        .type(T.F.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.ink)
                        .lineLimit(1)
                    if event.provable != nil {
                        Text("可证")
                            .type(T.F.kicker)
                            .foregroundStyle(T.C.ok)
                    }
                }
                Text(subtitle)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if event.flagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(T.C.danger)
            }

            Text(event.hasTime ? When.clock(event.time) : "无日期")
                .type(T.F.mono)
                // 「无日期」是信息，不是装饰：ink4 只有 2.3:1，读不出来。
                .foregroundStyle(T.C.ink3)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let who = event.whoName, !who.isEmpty {
            parts.append(who)
        } else if event.isOpen {
            parts.append("未归属")
        }
        if !event.credential.isEmpty { parts.append(event.credential) }
        if showLock { parts.append(event.lockName) }
        if let note = event.note, !note.isEmpty { parts.append(note) }
        if let diff = event.diff, !diff.isEmpty { parts.append(diff) }
        return parts.isEmpty ? "门锁事件" : parts.joined(separator: " · ")
    }
}

@MainActor
struct DayHead: View {
    var time: Int64
    /// 标题覆盖。锁端没有时钟的记录没有日期，分组标题是「没有日期」而不是 2010 年。
    var title: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text((title ?? When.dayTitle(time)).uppercased())
                .type(T.F.kicker)
                .foregroundStyle(T.C.ink3)
            Rectangle()
                .fill(T.C.hair)
                .frame(height: 0.5)
        }
        .padding(.top, 22)
        .padding(.bottom, 2)
    }
}
