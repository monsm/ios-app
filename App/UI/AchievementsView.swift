// ================= 成就页 (功能包18) =================
// 结构: 总览卡 → 徽章陈列架(988) → 安心夜月历(976/985) → 周目标(981) → 季度速览(1042)
//       → 四类成就墙(977/979/978/840/987) → 时光胶囊(1043) → 声音与通知(996/986)
// 只读 Milestones 结果, 不做统计; 庆祝动效统一走 Celebration.swift。
import SwiftUI
import UIKit

struct AchievementsView: View {
    @EnvironmentObject var app: AppState
    @State private var stats = MStats()
    @State private var unlocked: [String: Double] = [:]
    @State private var detail: Badge?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                headerCard.staggered(0)
                shelf.staggered(1)
                NightCalendarCard(onChange: refresh).staggered(2)
                weekGoal.staggered(3)
                quarterCard.staggered(4)
                wall.staggered(5)
                capsuleCard.staggered(6)
                togglesCard.staggered(7)
            }
            .padding(.vertical, DS.Space.m)
        }
        .dsScreenBackground()
        .navigationTitle("我的成就")
        .onAppear(perform: refresh)
        .sheet(item: $detail) { b in
            BadgeDetailSheet(badge: b, unlockedAt: unlocked[b.id])
        }
    }

    private func refresh() {
        stats = Milestones.loadStats()
        unlocked = Milestones.unlockedMap()
    }

    // ---------- 总览 (975 streak / 982 里程碑) ----------
    private var headerCard: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("徽章")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text("已点亮 \(unlocked.count) / \(Milestones.definitions.count) 枚")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: DS.Space.s) {
                    HeroPill(text: "连续 \(Milestones.streak().cur) 天",
                             systemImage: "flame.fill")
                    HeroPill(text: "累计开锁 \(Milestones.unlockTotal) 次",
                             systemImage: "flag.fill")
                }
            }
        }
    }

    // ---------- 徽章陈列架 (988) + 分享卡 (984) ----------
    private var shelf: some View {
        let latest = Milestones.latestUnlocked(3)
        return Card {
            SectionTitle(text: "徽章陈列架", count: latest.isEmpty ? nil : latest.count)
            if latest.isEmpty {
                Text("点亮的徽章会陈列在这里。先用一天, 成就自然会长出来。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: DS.Space.s) {
                    ForEach(latest, id: \.badge.id) { item in
                        BadgeTile(badge: item.badge, unlockedAt: item.at) { detail = item.badge }
                    }
                }
                Button {
                    shareCard(latest[0].badge, at: latest[0].at)
                } label: {
                    Label("把最新徽章做成分享卡", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    /// 984: 本地渲染玻璃卡存相册 (无网络)
    private func shareCard(_ b: Badge, at date: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        let card = BadgeShareCard(badge: b, dateText: f.string(from: date))
        let renderer = ImageRenderer(content: card.frame(width: 320, height: 400))
        renderer.scale = 3
        guard let img = renderer.uiImage else {
            app.showToast("分享卡生成失败")
            return
        }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        app.showToast("分享卡已存入相册")
    }

    // ---------- 981 周目标 ----------
    private var weekGoal: some View {
        let done = Milestones.weekDone
        let target = Milestones.weekTarget
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "star.fill")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(done >= target ? DS.Palette.warn : DS.Palette.textSub)
                        .accessibilityHidden(true)
                    Text("本周目标")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(1...7, id: \.self) { n in
                            Button("每周整理 \(n) 条") { Milestones.weekTarget = n; refresh() }
                        }
                    } label: {
                        Text("整理 \(target) 条")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
                ProgressView(value: Double(min(done, target)), total: Double(target))
                    .tint(DS.Palette.accent)
                Text(done >= target
                     ? "目标达成, 这颗星为你亮着"
                     : "本周已整理 \(done) / \(target) 条凭证")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 1042 季度速览 ----------
    private var quarterCard: some View {
        let q = Milestones.quarterSummary()
        return Card {
            SectionTitle(text: "本季速览")
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(q.unlocks > 0
                     ? "本季有归属的开门 \(q.unlocks) 次" + (q.topMember.isEmpty ? "" : ", \(q.topMember)最勤")
                     : "本季的归属开门记录还不多, 连上门锁读一次就有了")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(q.newCreds > 0 ? "新增凭证 \(q.newCreds) 条" : "本季暂无新增凭证")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ---------- 四类成就墙 (977/979/978/840/987) ----------
    private var wall: some View {
        Card {
            SectionTitle(text: "成就墙")
            VStack(alignment: .leading, spacing: DS.Space.l) {
                ForEach(BadgeCat.allCases) { cat in
                    let defs = Milestones.definitions.filter { $0.cat == cat }
                    let got = defs.filter { unlocked[$0.id] != nil }.count
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: cat.icon)
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(DS.Palette.accentText)
                                .accessibilityHidden(true)
                            Text(cat.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: 0)
                            Text("\(got)/\(defs.count)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        ProgressView(value: defs.isEmpty ? 0 : Double(got) / Double(defs.count))
                            .tint(DS.Palette.accent)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 4),
                                  spacing: DS.Space.s) {
                            ForEach(defs) { b in
                                BadgeTile(badge: b, unlockedAt: unlocked[b.id]) { detail = b }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- 时光胶囊 (1043) ----------
    @ViewBuilder
    private var capsuleCard: some View {
        if let c = Milestones.capsule() {
            Card {
                SectionTitle(text: "时光胶囊")
                if Milestones.capsuleIsOpen(c) {
                    Text(c.text)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("写于 \(Milestones.dayKey(Date(timeIntervalSince1970: c.at / 1000)))")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                } else {
                    Text("给未来留了一封信, \(c.openOn) 开启。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Card {
                SectionTitle(text: "时光胶囊")
                Text("写一段话封存起来, 在下一个结缘日打开。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    CapsuleComposeView(onSaved: refresh)
                } label: {
                    Label("写一封给一年后的信", systemImage: "envelope")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // ---------- 996/986 开关 ----------
    private var togglesCard: some View {
        Card {
            SectionTitle(text: "仪式感设置")
            Toggle("成就解锁通知", isOn: Binding(
                get: { Milestones.achNotify },
                set: { on in
                    DB.store.set("kf_ach_notify", on)
                    if on { Task { await CareReminders.requestAuthorization() } }
                }))
            Toggle("收集音效", isOn: Binding(
                get: { Milestones.collectSound },
                set: { DB.store.set("kf_collect_sound", $0) }))
        }
    }
}

// ---------- 徽章瓷片 (979 稀有度边 / 978 隐藏 / 840 未达成灰卡) ----------
struct BadgeTile: View {
    let badge: Badge
    var unlockedAt: Date?
    var action: () -> Void

    private var isUnlocked: Bool { unlockedAt != nil }

    private var ringColor: Color {
        switch badge.rarity {
        case .common: return DS.Palette.hairline
        case .rare: return DS.Palette.accent
        case .epic: return DS.Palette.accentText
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xxs) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt)
                        .frame(width: 56, height: 56)
                    Circle()
                        .strokeBorder(ringColor, lineWidth: isUnlocked ? 1.5 : 0.5)
                        .frame(width: 56, height: 56)
                    Image(systemName: hiddenLocked ? "questionmark" : badge.icon)
                        .font(.system(size: DS.Icon.md, weight: .medium))
                        .foregroundStyle(isUnlocked ? DS.Palette.accentText : DS.Palette.textSub)
                }
                .accessibilityHidden(true)
                Text(hiddenLocked ? "???" : badge.title)
                    .font(.caption2)
                    .foregroundStyle(isUnlocked ? DS.Palette.text : DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(tileA11y)
    }
    private var hiddenLocked: Bool { badge.hidden && !isUnlocked }
    private var tileA11y: String {
        if hiddenLocked { return "隐藏成就, 还差一点点" }
        if isUnlocked { return "徽章 \(badge.title), 已点亮" }
        return "未达成, \(badge.detail)"
    }
}

// ---------- 徽章详情 (840 触发条件 / 987 悬念进度) ----------
private struct BadgeDetailSheet: View {
    let badge: Badge
    let unlockedAt: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DS.Space.l) {
            BadgeTile(badge: badge, unlockedAt: unlockedAt, action: {})
                .buttonStyle(.plain)
                .disabled(true)
            VStack(spacing: DS.Space.s) {
                Text(badge.hidden && unlockedAt == nil ? "还差一点点" : badge.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(badge.hidden && unlockedAt == nil
                     ? "这是一枚隐藏成就, 达成的那一刻才会揭晓"
                     : badge.detail)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = unlockedAt {
                    Text("点亮于 \(Milestones.dayKey(at)) · \(badge.rarity.title)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                } else {
                    Text("稀有度: \(badge.rarity)")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }
}

// ---------- 984 分享卡内容 (供 ImageRenderer 渲染) ----------
private struct BadgeShareCard: View {
    let badge: Badge
    let dateText: String

    var body: some View {
        VStack(spacing: DS.Space.l) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 110, height: 110)
                Image(systemName: badge.icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(badge.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(badge.rarity.title + "徽章 · 点亮于 " + dateText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text("离线锁管家 · 本地生成")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 320, height: 400, alignment: .top)
        .background(DS.Gradient.hero, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// ---------- 安心夜月历 (976 打卡 / 985 补签) ----------
struct NightCalendarCard: View {
    var onChange: () -> Void
    @EnvironmentObject var app: AppState

    private var marks: [String: String] { Milestones.nightMarks() }

    var body: some View {
        Card {
            SectionTitle(text: "安心夜月历")
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("每晚十点后, 确认家里已是安心状态, 就为今晚点一颗星。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                grid
                HStack(spacing: DS.Space.s) {
                    if Milestones.canNightCheckIn {
                        if marks[Milestones.dayKey()] == nil {
                            Button {
                                if Milestones.checkInTonight() {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    app.showToast("今晚已安心打卡")
                                    onChange()
                                }
                            } label: {
                                Label("记录今晚的安心", systemImage: "moon.stars.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Palette.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: DS.Hit.min)
                                    .background(DS.Gradient.button,
                                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("记录今晚的安心")
                        } else {
                            Label("今晚已打卡, 晚安", systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.ok)
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                        }
                    } else {
                        Label("22 点后可打卡", systemImage: "moon.haze")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .leading)
                    }
                    if let day = Milestones.repairableDay {
                        Button {
                            if Milestones.repairDay(day) {
                                app.showToast("已为 \(Self.mdLabel(day)) 补上一颗星")
                                onChange()
                            }
                        } label: {
                            Label("补签 \(Self.mdLabel(day))", systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .padding(.horizontal, DS.Space.m)
                                .frame(minHeight: DS.Hit.min)
                                .background(DS.Palette.accentText.opacity(0.09),
                                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                Text("漏掉的日子每月可补签 1 次, 连续的温度不苛求完美。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var grid: some View {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let first = cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? now
        let lead = (cal.component(.weekday, from: first) + 5) % 7   // 周一为首
        let today = cal.component(.day, from: now)
        let week = ["一", "二", "三", "四", "五", "六", "日"]
        return VStack(spacing: DS.Space.xxs) {
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { w in
                    Text(w)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: DS.Space.xxs) {
                ForEach(0..<(lead + days), id: \.self) { i in
                    if i < lead {
                        Color.clear.frame(height: 30)
                    } else {
                        let d = i - lead + 1
                        dayCell(d: d, isToday: d == today)
                    }
                }
            }
        }
    }

    private func dayCell(d: Int, isToday: Bool) -> some View {
        let key = String(Milestones.monthKey()) + String(format: "-%02d", d)
        let mark = marks[key]
        return VStack(spacing: 2) {
            Text("\(d)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isToday ? DS.Palette.accentText : DS.Palette.textSub)
            if mark == "ok" {
                Circle().fill(DS.Palette.accent).frame(width: 5, height: 5)
            } else if mark == "repair" {
                Circle().strokeBorder(DS.Palette.warn, lineWidth: 1).frame(width: 5, height: 5)
            } else {
                Color.clear.frame(width: 5, height: 5)
            }
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d) 日" + (mark == nil ? "" : mark == "ok" ? ", 已打卡" : ", 补签"))
    }

    static func mdLabel(_ key: String) -> String {
        let p = key.split(separator: "-")
        return p.count == 3 ? "\(Int(p[1]) ?? 0)月\(Int(p[2]) ?? 0)日" : key
    }
}

// ---------- 时光胶囊撰写 (1043) ----------
struct CapsuleComposeView: View {
    var onSaved: () -> Void = {}
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityLabel("胶囊内容")
            } header: {
                Text("给一年后的自己")
            } footer: {
                Text(Milestones.bondDay.isEmpty
                     ? "封存一年后开启。添加门锁后, 会自动改到结缘日开启。"
                     : "封存后将在结缘日 \(nextBondDay()) 开启, 全程只存在本机。")
            }
            Section {
                BusyButton(title: "封存胶囊", systemImage: "envelope.badge.clock",
                           isBusy: false, disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Milestones.saveCapsule(text)
                    app.showToast("胶囊已封存")
                    onSaved()
                    dismiss()
                }
            }
        }
        .navigationTitle("时光胶囊")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private func nextBondDay() -> String {
        let b = Milestones.bondDay
        let md = String(b.suffix(5))
        let y = Calendar.current.component(.year, from: Date())
        let cand = "\(y)-\(md)"
        return cand > Milestones.dayKey() ? cand : "\(y + 1)-\(md)"
    }
}

// ================= 关怀提醒与公告板 (1010/991/1044) =================
struct CareRemindersView: View {
    @EnvironmentObject var app: AppState
    @State private var bulletin = Milestones.bulletin

    var body: some View {
        Form {
            Section {
                TextField("写一句常驻家里的话", text: $bulletin)
                    .submitLabel(.done)
                    .onSubmit { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
            } header: {
                Text("家庭公告板")
            } footer: {
                Text("这句话会出现在各页面的空态里, 像贴在门后的一张便签。")
            }

            Section {
                LabeledRow("结缘日", Milestones.bondDay.isEmpty ? "添加门锁后自动记录" : Milestones.bondDay)
                Toggle("结缘纪念日提醒", isOn: Binding(
                    get: { CareReminders.annivOn },
                    set: { on in
                        DB.store.set("kf_care_anniv", on)
                        Task { await CareReminders.reschedule() }
                    }))
            } header: {
                Text("纪念日")
            }

            Section {
                Toggle("成员生日提醒 (提前一天)", isOn: Binding(
                    get: { CareReminders.bdayOn },
                    set: { on in
                        DB.store.set("kf_care_bday", on)
                        Task { await CareReminders.reschedule() }
                    }))
                ForEach(DB.members()) { m in
                    HStack {
                        Text(m.name)
                        Spacer(minLength: DS.Space.m)
                        Text(Milestones.memberBirthdays()[m.id] ?? "未填写")
                            .foregroundStyle(Milestones.memberBirthdays()[m.id] == nil
                                             ? DS.Palette.textSub : DS.Palette.text)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("成员生日")
            } footer: {
                Text("生日在 设置-成员管理-补全信息 里填写 (格式 MM-dd)。提醒通过本地通知送达, 全程离线, 不依赖任何服务器。")
            }
        }
        .navigationTitle("关怀提醒")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .onDisappear { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
