// 凭证到期月历 —— 2026-10-29 新增
//
// 来源：`CredentialOrg.monthDeadlines`（每天到期凭证数）与 `dayDeadlines`（某天到期的凭证列表）
// 两函数有完整实现、零调用 —— 用户在凭证页看不到「这个月哪天有东西到期」。
//
// 设计取向：
//   · 只做「到期」这一件事，不把日历做成第二个台账列表；
//   · 格子里只有数字角标，点开才出当天清单（避免一屏几百条）；
//   · 到期判断走 `CredentialOrg.expiryDate`（与凭证列表的「已过期/即将过期」同一口径）。
import SwiftUI

struct CredentialCalendarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var monthAnchor = Date()
    @State private var picked: Date?

    private var mac: String { app.current?.mac ?? "" }

    private var cal: Calendar {
        var c = WeekCal.gregorian
        c.timeZone = TimeZone.current
        return c
    }

    private var year: Int { cal.component(.year, from: monthAnchor) }
    private var month: Int { cal.component(.month, from: monthAnchor) }

    private var deadlines: [Date: Int] {
        CredentialOrg.monthDeadlines(mac, year: year, month: month)
    }

    /// 当月 1 号是周几（1 = 周日 … 7 = 周六），用于补前置空格。
    private var leadingBlanks: Int {
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return cal.component(.weekday, from: first) - 1
    }

    private var dayCount: Int {
        cal.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }

    var body: some View { vkBody.destined(.credentialCalendar) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { shift(-1) } label: {
                            Image(systemName: "chevron.left").frame(width: DS.Hit.min, height: DS.Hit.min)
                        }
                        .accessibilityLabel("上一个月")
                        Spacer()
                        Text("\(String(year)) 年 \(month) 月")
                            .vkFont(.headline)
                            .monospacedDigit()
                        Spacer()
                        Button { shift(1) } label: {
                            Image(systemName: "chevron.right").frame(width: DS.Hit.min, height: DS.Hit.min)
                        }
                        .accessibilityLabel("下一个月")
                    }
                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                        ForEach(1...dayCount, id: \.self) { d in dayCell(d) }
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text(summaryLine)
                }

                if let d = picked {
                    Section {
                        let items = CredentialOrg.dayDeadlines(mac, d)
                        if items.isEmpty {
                            Text("这一天没有到期的凭证。")
                                .vkFont(.footnote)
                                .foregroundStyle(DS.Palette.textSub)
                        } else {
                            ForEach(items, id: \.alias) { p in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(CredentialOrg.displayPwd(p))
                                        .vkFont(.footnote)
                                    Text(detailLine(p))
                                        .vkFont(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                            }
                        }
                    } header: {
                        Text(dayTitle(d))
                    }
                }
            }
            .navigationTitle("到期月历")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                Text(w)
                    .vkFont(.caption2, weight: .semibold)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ d: Int) -> some View {
        let date = cal.date(from: DateComponents(year: year, month: month, day: d)) ?? Date()
        let n = deadlines[date] ?? 0
        let on = picked.map { cal.isDate($0, inSameDayAs: date) } ?? false
        Button {
            picked = on ? nil : date
        } label: {
            VStack(spacing: 1) {
                Text("\(d)")
                    .vkFont(.caption.monospacedDigit())
                    .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                if n > 0 {
                    Text("\(n)")
                        .vkFont(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.warn)
                } else {
                    Text(" ").vkFont(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? DS.Palette.accent : (n > 0 ? DS.Palette.warn.opacity(0.12) : DS.Palette.surfaceAlt))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month) 月 \(d) 日" + (n > 0 ? "，\(n) 条到期" : ""))
    }

    private var summaryLine: String {
        let total = deadlines.values.reduce(0, +)
        if total == 0 { return "这个月没有凭证到期。" }
        let days = deadlines.count
        return "这个月有 \(total) 条凭证到期，分布在 \(days) 天。点某一天看清单。"
    }

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        return f.string(from: d)
    }

    private func detailLine(_ p: LedgerPwd) -> String {
        var bits: [String] = []
        if let to = CredentialOrg.expiryDate(p) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "HH:mm 到期"
            bits.append(f.string(from: to))
        }
        if p.temp { bits.append("临时码") }
        if let own = p.owner, !own.isEmpty, let m = DB.member(own) { bits.append(m.name) }
        return bits.isEmpty ? "—" : bits.joined(separator: " · ")
    }

    private func shift(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = d
            picked = nil
        }
    }
}
