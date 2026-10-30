// 凭证到期月历 —— 2026-10-29 新增
//
// 来源：`CredentialOrg.monthDeadlines`（每天到期凭证数）与 `dayDeadlines`（某天到期的凭证列表）
// 两函数有完整实现、零调用 —— 用户在凭证页看不到「这个月哪天有东西到期」。
//
// 设计取向：
//   · 只做「到期」这一件事，不把日历做成第二个台账列表；
//   · 格子里只有数字角标，点开才出当天清单（避免一屏几百条）；
//   · 到期判断只走 `CredentialOrg.expiryDate`（按「到期日」）；凭证列表那侧还多一档
//     `isEarlyExpired` / `effectiveExpiry`（提前 N 分钟失效），本页**不含**那一档 ——
//     2026-10-30 修正原注释「与凭证列表同一口径」的夸大说法。
import SwiftUI

struct CredentialCalendarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

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

    /// 2026-10-30 修复（第 115 轮，**性能**）：`deadlines` 原来是计算属性（内部 `monthDeadlines` 每次遍历台账 + 逐条解析日期），
    /// 却被 31 个日格逐个取下标、footer 再读一次 ⇒ 一次渲染 30+ 次台账扫描。改 @State 按月缓存。
    @State private var deadlines: [Date: Int] = [:]

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
                    .padding(.vertical, DS.Space.xxs)
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
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
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
        .task(id: monthAnchor) {
            deadlines = CredentialOrg.monthDeadlines(mac, year: year, month: month)
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
        HStack(spacing: DS.Space.xs) {
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
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(on ? DS.Palette.accent : (n > 0 ? DS.Palette.warn.opacity(0.12) : DS.Palette.surfaceAlt))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month) 月 \(d) 日" + (n > 0 ? "，\(n) 条到期" : ""))
    }

    private var summaryLine: String {
        // 2026-10-30 修复（第 119 轮）：无锁时 `mac` 是空串、`deadlines` 恒空，
        // 原文案会把「没有锁」说成「这个月没有凭证到期」。
        guard !mac.isEmpty else { return "还没有添加门锁 —— 先在设备页添加一把锁。" }
        let total = deadlines.values.reduce(0, +)
        if total == 0 { return "这个月没有凭证到期。" }
        let days = deadlines.count
        return "这个月有 \(total) 条凭证到期，分布在 \(days) 天。点某一天看清单。"
    }

    private func dayTitle(_ d: Date) -> String {
        let f = DF.cached("M 月 d 日 EEEE", locale: "zh_CN")
        return f.string(from: d)
    }

    private func detailLine(_ p: LedgerPwd) -> String {
        var bits: [String] = []
        if let to = CredentialOrg.expiryDate(p) {
            let f = DF.cached("HH:mm 到期", locale: "zh_CN")
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
