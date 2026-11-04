// KeyCalendarHomeScreen.swift —— 到期月历（V8 设计语言）
//
// 与 KeyCalendarScreen 的能力对齐：把有限期凭证的到期日摆到月历上（每格只有条数），
// 点某一天看当天清单，点清单某条进凭证详情。只做"到期"一件事。
import SwiftUI
import Foundation

struct KeyCalendarHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var monthAnchor = Date()
    @State private var pickedDay: String?

    private var calendar: Calendar { TimeFormat.calendar }
    private var year: Int { calendar.component(.year, from: monthAnchor) }
    private var month: Int { calendar.component(.month, from: monthAnchor) }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30 }

    private var leadingBlanks: Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return calendar.component(.weekday, from: first) - 1
    }

    private var monthPrefix: String { String(format: "%04d-%02d", year, month) }

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

    private var monthTotal: Int { deadlines.values.reduce(0) { $0 + $1.count } }
    private var pickedItems: [KeyItem] { deadlines[pickedDay ?? ""] ?? [] }

    private var hasAnyExpiry: Bool { app.keys.contains { $0.expiresAt != nil } }

    var body: some View {
        VPage(title: "到期月历", lead: monthTotal > 0
              ? "\(year) 年 \(month) 月 · \(monthTotal) 条到期"
              : "\(year) 年 \(month) 月 · 这个月没有凭证到期") {
            EmptyView()
        } content: {
            if !hasAnyExpiry {
                VEmpty(
                    title: "还没有有限期的凭证",
                    reason: "月历只画有限期的东西。给保洁发一张 7 天临时码，或把某枚密码设成有到期日，这里就会有格子亮起来。",
                    actionTitle: "新增凭证"
                ) { router.request(.dest(.keyCreate)) }
            } else {
                calendarCard
                if pickedDay != nil {
                    dayCard
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarCard: some View {
        VCard2 {
            HStack(spacing: V8.S.gapS) {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.ink1)
                        .frame(width: V8.H.min, height: V8.H.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一个月")
                Spacer(minLength: 0)
                Text(String(format: "%04d-%02d", year, month))
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(V8.T.chipValue)
                        .foregroundStyle(V8.C.ink1)
                        .frame(width: V8.H.min, height: V8.H.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一个月")
            }
            HStack(spacing: V8.S.gapXS) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { word in
                    Text(word)
                        .font(V8.T.micro)
                        .foregroundStyle(V8.C.ink4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, V8.S.gapM)
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: V8.S.gapXS), count: 7),
                      spacing: V8.S.gapXS) {
                ForEach(0 ..< leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: V8.H.min)
                }
                ForEach(1 ... dayCount, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let dayKey = monthPrefix + "-" + String(format: "%02d", day)
        let count = deadlines[dayKey]?.count ?? 0
        let selected = pickedDay == dayKey
        return Button {
            pickedDay = selected ? nil : dayKey
        } label: {
            VStack(spacing: V8.S.gapXS / 2) {
                Text("\(day)")
                    .font(V8.T.caption)
                    .foregroundStyle(selected ? V8.C.ink1 : V8.C.ink3)
                    .monospacedDigit()
                if count > 0 {
                    Text("\(count)")
                        .font(V8.T.micro)
                        .foregroundStyle(selected ? V8.C.ink1 : V8.C.warn)
                        .monospacedDigit()
                } else {
                    Color.clear.frame(height: V8.S.gapM)
                }
            }
            .frame(maxWidth: .infinity, minHeight: V8.H.min)
            .background(
                RoundedRectangle(cornerRadius: V8.R.inset, style: .continuous)
                    .fill(selected ? V8.C.chipOff : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month) 月 \(day) 日" + (count > 0 ? "，\(count) 条到期" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var dayCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当天清单", statement: "\(pickedItems.count) 条到期",
                      trailing: pickedDay)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if pickedItems.isEmpty {
                Text("这一天没有到期的凭证。点别的有数字的格子看看。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(pickedItems) { key in
                        Button {
                            KeysRoute.openDetail(key.id, router: router)
                        } label: {
                            VDataRow(tag: key.kind.rawValue, tagTint: kindTint(key.kind), title: key.name,
                                     detail: CredentialOrg.ownerName(key.owner),
                                     value: KeysState.word(key, now: KeysState.now()))
                        }
                        .buttonStyle(.plain)
                        if key.id != pickedItems.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func kindTint(_ kind: KeyItem.Kind) -> Color {
        switch kind {
        case .password: return V8.D.password
        case .fingerprint: return V8.D.fingerprint
        case .temp: return V8.D.temp
        case .mobile: return V8.D.mobile
        }
    }

    private func shift(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
            pickedDay = nil
        }
    }
}
