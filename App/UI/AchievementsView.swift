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

    var body: some View { vkBody.destined(.achievements) }
    var vkBody: some View {
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
            BadgeDetailSheet(badge: b, unlockedAt: Milestones.unlockedDate(b.id))
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
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.heroFg.opacity(0.85))
                    .lineLimit(1)
                Text("已点亮 \(unlocked.count) / \(Milestones.definitions.count) 枚")
                    .vkFont(.title3, weight: .semibold)
                    .foregroundStyle(DS.heroFg)   // 863: 坐在 HeroCard 上, 不能写死白
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
                // 包14 空态族消费点 (841 小管家默认开 / 834 演示链真上屏 / 1044 便签):
                // 旧文案只有一句"点亮的徽章会陈列在这里" —— 现在给得出动作: 演示链开演示锁,
                // 玩几下圆盘, 陈列架与墙都会跟着长起来 (数据全 demo_, 横幅一键清除)。
                GuidedEmptyView(systemImage: "rosette",
                                title: "陈列架还空着",
                                message: "先用一天, 成就自然会长出来; 也可以先看 30 秒演示, 用演示锁玩出第一批时刻。",
                                demoAction: {
                                    DemoKit.setOn(true)
                                    app.loadDevices()
                                    app.showToast("演示锁已就位: 去设备页点圆盘, 顶部横幅可一键清除")
                                })
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
                        .vkFont(.subheadline, weight: .medium)
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
        // 2026-10-14: 钉公历 + POSIX —— 否则泰历/民国/和历等系统区域会把 2026 打成 2569 等。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年M月d日"
        let card = BadgeShareCard(badge: b, dateText: f.string(from: date))
        let renderer = ImageRenderer(content: card.frame(width: 320, height: 400))
        renderer.scale = 3
        guard let img = renderer.uiImage else {
            app.showToast("分享卡生成失败")
            return
        }
        // 2026-10-15 走查: 这句原先是"分享卡已存入相册" —— 而 `UIImageWriteToSavedPhotosAlbum` 是**异步**的,
        // 第三个参数 (completion target) 这里传的是 nil, 意味着成功与失败本行代码一概不知道;
        // 首次还会等用户点"允许" (project.yml 里那条 NSPhotoLibraryAddUsageDescription), 拒绝就是没存。
        // 回调拿不到 ⇒ 就不该报"已存入"。改成说这一按真正做的事。
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        app.showToast("已提交相册保存 · 首次会弹允许框, 没允许就没存进去")
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
                        .vkFont(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(1...7, id: \.self) { n in
                            Button("每周整理 \(n) 条") { Milestones.weekTarget = n; refresh() }
                        }
                    } label: {
                        Text("整理 \(target) 条")
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                ProgressView(value: Double(min(done, target)), total: Double(target))
                    .tint(DS.Palette.accent)
                Text(done >= target
                     ? "目标达成, 这颗星为你亮着"
                     : "本周已整理 \(done) / \(target) 条凭证")
                    .vkFont(.footnote)
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
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(q.newCreds > 0 ? "新增凭证 \(q.newCreds) 条" : "本季暂无新增凭证")
                    .vkFont(.caption)
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
                                .vkFont(.subheadline, weight: .semibold)
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: 0)
                            Text("\(got)/\(defs.count)")
                                .vkFont(.caption, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        ProgressView(value: defs.isEmpty ? 0 : Double(got) / Double(defs.count))
                            .tint(DS.Palette.accent)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 4),
                                  spacing: DS.Space.s) {
                            ForEach(defs) { b in
                                BadgeTile(badge: b, unlockedAt: Milestones.unlockedDate(b.id)) { detail = b }
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
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("写于 \(Milestones.dayKey(Date(timeIntervalSince1970: c.at / 1000)))")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                } else {
                    Text("给未来留了一封信, \(c.openOn) 开启。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Card {
                SectionTitle(text: "时光胶囊")
                Text("写一段话封存起来, 在下一个结缘日打开。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    CapsuleComposeView(onSaved: refresh)
                } label: {
                    Label("写一封给一年后的信", systemImage: "envelope")
                        .vkFont(.subheadline, weight: .medium)
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
            VariantToggle("成就解锁通知", isOn: Binding(
                get: { Milestones.achNotify },
                set: { on in
                    DB.store.set("kf_ach_notify", on)
                    if on { Task { await CareReminders.requestAuthorization() } }
                }))
            VariantToggle("收集音效", isOn: Binding(
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
                    .vkFont(.caption2)
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
        return "未达成, 还差一点点, 达成条件 \(badge.detail)"   // 987 悬念行 + 840 条件
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
                    .vkFont(.title3, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                // 987 悬念进度与 840 (未达成直显触发条件) 相抵: 取两面都留 ——
                // 未达成一律先给"还差一点点"悬念行 (不说还差多少, 本地也没有进度量可报),
                // 非隐藏徽章的达成条件保留在后 (840 的用途: 让人知道怎么拿到), 隐藏徽章仍不揭底 (978)。
                if unlockedAt == nil, !badge.hidden {
                    Text("还差一点点")
                        .vkFont(.footnote, weight: .medium)
                        .foregroundStyle(DS.Palette.textSub)
                }
                Text(badge.hidden && unlockedAt == nil
                     ? "这是一枚隐藏成就, 达成的那一刻才会揭晓"
                     : badge.detail)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = unlockedAt {
                    Text("点亮于 \(Milestones.dayKey(at)) · \(badge.rarity.title)")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.accentText)
                } else {
                    Text("稀有度: \(badge.rarity)")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        // 33 玻璃 sheet 底 (令牌见 DesignSystem dsSheetGlass): 降透明开启时自动落回实底 surface
        .dsSheetGlass()
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
                    .fill(DS.heroFg.opacity(0.16))
                    .frame(width: 110, height: 110)
                Image(systemName: badge.icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(DS.heroFg)
            }
            Text(badge.title)
                .vkFont(.title2, weight: .semibold)
                .foregroundStyle(DS.heroFg)
            Text(badge.rarity.title + "徽章 · 点亮于 " + dateText)
                .vkFont(.footnote)
                .foregroundStyle(DS.heroFg.opacity(0.85))
            Spacer()
            Text("离线锁管家 · 本地生成")
                .vkFont(.caption2)
                .foregroundStyle(DS.heroFg.opacity(0.7))
        }
        .padding(DS.Space.xl)
        .frame(width: 320, height: 400, alignment: .top)
        .background(DS.heroGradientSafe, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
                    .vkFont(.footnote)
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
                                    .vkFont(.subheadline, weight: .medium)
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
                                .vkFont(.footnote)
                                .foregroundStyle(DS.Palette.ok)
                                .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
                        }
                    } else {
                        Label("22 点后可打卡", systemImage: "moon.haze")
                            .vkFont(.caption)
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
                                .vkFont(.subheadline, weight: .medium)
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
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var grid: some View {
        let cal = WeekCal.gregorian
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
                        .vkFont(.caption2)
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
                .vkFont(.caption2)
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

    var body: some View { vkBody.destined(.capsuleCompose) }
    var vkBody: some View {
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
        .variantList()
        .dsScreenBackground()
    }

    private func nextBondDay() -> String {
        let b = Milestones.bondDay
        let md = String(b.suffix(5))
        let y = WeekCal.gregorian.component(.year, from: Date())
        let cand = "\(y)-\(md)"
        return cand > Milestones.dayKey() ? cand : "\(y + 1)-\(md)"
    }
}

// ================= 关怀提醒与公告板 (1010/991/1044) =================
struct CareRemindersView: View {
    @EnvironmentObject var app: AppState
    @State private var bulletin = Milestones.bulletin

    var body: some View { vkBody.destined(.careReminders) }
    var vkBody: some View {
        Form {
            Section {
                TextField("写一句常驻家里的话", text: $bulletin)
                    .submitLabel(.done)
                    .onSubmit { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
            } header: {
                Text("家庭公告板")
            } footer: {
                // 1044 消费点如实列名 (原句"各页面的空态"是超售): 设备页/记录页空态直挂,
                // 引导空态卡 (设置门锁空态、成就陈列架、维护历史、诊断日志) 经 GuidedEmptyView 消费。
                Text("这句便签已贴在这几处空态旁: 设备页、记录页, 以及走引导空态卡的页面 (设置门锁空态、成就陈列架、维护历史、诊断日志)。未接入的空态不会偷偷显示, 后续批次补。")
                    .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledRow("结缘日", Milestones.bondDay.isEmpty ? "添加门锁后自动记录" : Milestones.bondDay)
                VariantToggle("结缘纪念日提醒", isOn: Binding(
                    get: { CareReminders.annivOn },
                    set: { on in
                        DB.store.set("kf_care_anniv", on)
                        Task { await CareReminders.reschedule() }
                    }))
            } header: {
                Text("纪念日")
            }

            Section {
                VariantToggle("成员生日提醒 (提前一天)", isOn: Binding(
                    get: { CareReminders.bdayOn },
                    set: { on in
                        DB.store.set("kf_care_bday", on)
                        Task { await CareReminders.reschedule() }
                    }))
                ForEach(DB.members()) { m in
                    HStack(spacing: DS.Space.s) {
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
        .variantList()
        .dsScreenBackground()
        .onDisappear { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
