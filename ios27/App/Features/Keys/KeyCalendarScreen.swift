// KeyCalendarScreen.swift —— 到期月历。
//
// 这一屏干什么：把这把锁所有有限期凭证的到期日摆到月历上（每格只有到期条数），
// 点某一天才出当天清单。只做「到期」一件事，不做第二个台账列表。
// 数据从哪来：AppModel.keys 里 expiresAt 非空的条目，按自然日归集（与列表同一口径）。
// 主动作：点某一天 → 当天清单 → 点某一条 → 凭证详情。
import SwiftUI
import Foundation

struct KeyCalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var monthAnchor = Date()
    @State private var pickedDay: String?

    private var calendar: Calendar { TimeFormat.calendar }

    private var year: Int { calendar.component(.year, from: monthAnchor) }
    private var month: Int { calendar.component(.month, from: monthAnchor) }

    private var dayCount: Int {
        calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }

    /// 当月 1 号是周几（1 = 周日 … 7 = 周六），用于补前置空格。
    private var leadingBlanks: Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return calendar.component(.weekday, from: first) - 1
    }

    /// 每天到期的条数。键是 dayKey（yyyy-MM-dd），与台账分组同一口径。
    private var deadlines: [String: [KeyItem]] {
        var buckets: [String: [KeyItem]] = [:]
        for key in app.keys {
            guard let expiresAt = key.expiresAt else { continue }
            let dayKey = TimeFormat.dayKey(expiresAt)
            guard dayKey.hasPrefix(monthPrefix) else { continue }
            buckets[dayKey, default: []].append(key)
        }
        return buckets
    }

    private var monthPrefix: String {
        String(format: "%04d-%02d", year, month)
    }

    private var monthTotal: Int { deadlines.values.reduce(0) { $0 + $1.count } }

    private var pickedItems: [KeyItem] { deadlines[pickedDay ?? ""] ?? [] }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与门页同一配方）。
        // 月历格子**保留自绘**（系统 `DatePicker` 不接受自定义格子：每格要显示到期条数），
        // 所以月历仍是一张 `VCard`，用 `cardRow()` 放进 List（`.plain` 样式没有系统左右留白，
        // cardRow 补回 pageGutter）；只有「当天清单」是行式内容 → `Section`。
        List {
            header.headerRow()
            if app.keys.filter({ $0.expiresAt != nil }).isEmpty {
                emptyBlock.cardRow()
            } else {
                calendarPanel.cardRow()
                if let pickedDay {
                    daySection(pickedDay)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("到期月历")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("到期月历")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: monthTotal > 0 ? .attention : .neutral,
                         word: monthTotal > 0 ? "本月有到期" : "本月无到期")
                Text(monthTotal > 0 ? "\(year) 年 \(month) 月 · \(monthTotal) 条到期" : "\(year) 年 \(month) 月 · 这个月没有凭证到期")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：月历

    private var calendarPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                HStack(spacing: V.S.gapS) {
                    Button {
                        shift(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                            .font(V.F.icon18Medium)
                            .foregroundStyle(V.C.text1)
                            .frame(width: V.Hit.min, height: V.Hit.min)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上一个月")
                    Spacer(minLength: 0)
                    VReading(value: String(format: "%04d-%02d", year, month), font: V.F.number17)
                    Spacer(minLength: 0)
                    Button {
                        shift(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                            .font(V.F.icon18Medium)
                            .foregroundStyle(V.C.text1)
                            .frame(width: V.Hit.min, height: V.Hit.min)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一个月")
                }
                weekdayHeader
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V.S.gapXS), count: 7),
                          spacing: V.S.gapXS) {
                    ForEach(0 ..< leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: V.Hit.min)
                    }
                    ForEach(1 ... dayCount, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: V.S.gapXS) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { word in
                Text(word)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayCell(_ day: Int) -> some View {
        let dayKey = monthPrefix + "-" + String(format: "%02d", day)
        let count = deadlines[dayKey]?.count ?? 0
        let selected = pickedDay == dayKey
        return Button {
            pickedDay = selected ? nil : dayKey
        } label: {
            VStack(spacing: V.S.gapXXS) {
                VReading(value: "\(day)", font: V.F.number13,
                        tint: selected ? V.C.text1 : V.C.text2, animated: false)
                if count > 0 {
                    VReading(value: "\(count)", font: V.F.number11,
                            tint: selected ? V.C.text1 : V.C.warning, animated: false)
                } else {
                    Color.clear.frame(height: V.S.gapMS)
                }
            }
            .frame(maxWidth: .infinity, minHeight: V.Hit.min)
            .background(selected ? V.C.blue.opacity(0.16) : (count > 0 ? V.C.cardAlt : Color.clear),
                        in: .rect(cornerRadius: V.R.control))
            .overlay {
                RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                    .strokeBorder(selected ? V.C.blue.opacity(0.75) : Color.clear, lineWidth: V.S.hair)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month) 月 \(day) 日" + (count > 0 ? "，\(count) 条到期" : "，没有到期"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: 当天清单

    /// 当天清单 = 系统 `Section`：一行一枚凭证，点行进详情。
    private func daySection(_ dayKey: String) -> some View {
        Section {
            if pickedItems.isEmpty {
                KeysInlineNote(tone: .neutral, text: "这一天没有到期的凭证。点别的有数字的格子看看。")
            } else {
                ForEach(pickedItems) { key in
                    Button {
                        KeysRoute.openDetail(key.id, router: router)
                    } label: {
                        KeysRow(key: key, now: KeysState.now())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardPad, bottom: 0, trailing: V.S.cardPad))
                    .accessibilityHint("打开凭证详情")
                }
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text(TimeFormat.dayTitle(dayKey))
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Text("\(pickedItems.count) 条")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
            }
            .textCase(nil)
        }
    }

    // MARK: 空态（给出路）

    private var emptyBlock: some View {
        VCard {
            VEmptyState(
                title: "还没有有限期的凭证",
                message: "月历只画有限期的东西。给保洁发一张 7 天临时码，或把某枚密码设成有到期日，这里就会有格子亮起来。",
                actionTitle: "新增临时码",
                systemImage: "calendar"
            ) {
                router.request(.dest(.keyCreate))
            }
            .padding(.vertical, V.S.gapXXL)
        }
    }

    private func shift(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = next
        pickedDay = nil
    }
}