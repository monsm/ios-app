// 包4 维护关怀页面 — 维护中心 / 五项保养清单 / 换电图文指引 / 维护提醒设置
// 落地: 1012 年度换电日 · 1013 90 天周期 · 1014 事件入记录 · 1015 五项清单 · 1025 应急钥匙半年检 ·
//       1024 潮湿位 · 1026 低温关怀 · 1028 保养历史过滤 · 1030 清洁月历 · 1031/1038 免扰与白天送达 ·
//       116 换电图文引导 · 118 换电复位基线 · 1033 换电向导 (与 116 同一页: 分步图文 + 「已换新」完成写记录, 不重复造页) ·
//       287 低电阈值 · 146 升级提醒开关 · 1039/爱洁之家徽章联动
import SwiftUI

// ================= 维护中心 (锁详情页/设置入口, per-lock) =================
struct MaintenanceView: View {
    @EnvironmentObject var app: AppState
    @State private var care = CareState()
    @State private var yearlyOn = false
    @State private var yearlyDate = Date()
    @State private var ekeyOn = false
    @State private var loaded = false
    @State private var showChecklist = false

    private var mac: String { app.current?.mac ?? "" }
    private var meta: LockMeta { LockArchive.meta(mac) }
    /// 1022 频次自适应: 高频使用锁 (近 30 天开门 ≥60 次) 保养周期自适应缩短到 60 天
    private var opens30d: Int {
        guard let u = LockStats.usage().first(where: { $0.mac == mac }) else { return 0 }
        return u.opens30d
    }
    private var periodDays: Int { opens30d >= 60 ? 60 : 90 }
    /// 1013 周期已过天数 / 是否到期
    private var elapsedDays: Double {
        guard care.lastCareAt > 0 else { return 0 }
        return (Date().timeIntervalSince1970 * 1000 - care.lastCareAt) / 86400_000
    }
    private var careDue: Bool { care.lastCareAt > 0 && elapsedDays >= Double(periodDays) }

    var body: some View {
        Form {
            carePeriodSection      // 1013/1015
            careMarksSection       // 1030
            historySection         // 1028/1014
            swapSection            // 116/118/1012
            ekeySection            // 1025
            environmentSection     // 1024/1026
        }
        .navigationTitle("维护与保养")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .onAppear { if !loaded { loaded = true; reload() } }
        .sheet(isPresented: $showChecklist) { CareChecklistView { reload() } }
        .onChange(of: yearlyOn) { _, _ in saveYearly() }
        .onChange(of: yearlyDate) { _, _ in saveYearly() }
    }

    private func reload() {
        care = BatteryCare.care(mac)
        ekeyOn = care.ekeyRemindOn
        yearlyOn = !care.yearlyBattDay.isEmpty
        let p = care.yearlyBattDay.split(separator: "-").compactMap { Int($0) }
        if p.count == 2,
           let d = Calendar.current.date(from: DateComponents(year: 2000, month: p[0], day: p[1])) {
            yearlyDate = d
        }
    }
    private func saveYearly() {
        var s = BatteryCare.care(mac)
        if yearlyOn {
            let p = Calendar.current.dateComponents([.month, .day], from: yearlyDate)
            s.yearlyBattDay = String(format: "%02d-%02d", p.month ?? 1, p.day ?? 1)
        } else {
            s.yearlyBattDay = ""
        }
        BatteryCare.saveCare(mac, s)
        care = s
        Task { await CareSchedule.rescheduleCalendar() }
    }
    /// 1034: 充电记录弹窗 (日期记今天, 时长可留空)
    private func markCharge() {
        let alert = UIAlertController(title: "充电记录", message: "将把上次充电记为今天", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "充电时长 (分钟, 可留空)"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "记录", style: .default) { _ in
            var s = BatteryCare.care(mac)
            s.chargeAt = Date().timeIntervalSince1970 * 1000
            s.chargeLenMin = Int(alert.textFields?.first?.text ?? "") ?? 0
            BatteryCare.saveCare(mac, s)
            care = s
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }
    private func saveEkey() {
        var s = BatteryCare.care(mac)
        s.ekeyRemindOn = ekeyOn
        BatteryCare.saveCare(mac, s)
        care = s
        Task { await CareSchedule.rescheduleCalendar() }
    }
    private func daysAgoText(_ tsMs: Double) -> String {
        let d = Int(Date().timeIntervalSince1970 * 1000 - tsMs) / 86_400_000
        return d <= 0 ? "今天" : "\(d) 天前"
    }

    // ---------- 1013 90 天周期 + 1015 五项入口 ----------
    private var carePeriodSection: some View {
        Section {
            LabeledRow("上次保养", care.lastCareAt > 0 ? daysAgoText(care.lastCareAt) : "还没记过")
            if care.lastCareAt > 0 {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Palette.surfaceAlt)
                            Capsule().fill(careDue ? DS.Palette.warn : DS.Palette.accent)
                                .frame(width: geo.size.width * CGFloat(min(elapsedDays / Double(periodDays), 1)))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                    Text(careDue
                         ? "已满 \(periodDays) 天, 建议安排一次保养"
                         : "周期 \(periodDays) 天 · 已过 \(Int(elapsedDays)) 天" + (periodDays == 60 ? " · 高频使用自动缩短" : ""))
                        .font(.caption2)
                        .foregroundStyle(careDue ? DS.Palette.warn : DS.Palette.textSub)
                }
                .accessibilityElement(children: .combine)
            }
            Button { showChecklist = true } label: {
                Label(care.lastCareAt > 0 ? "再做一次五项保养" : "开始五项保养", systemImage: "checklist")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Text("保养周期")
        } footer: {
            Text("五项: 滑轨 / 锁舌 / 电池触点 / 指纹头 / 应急钥匙。完成即写入记录, 可在记录页按「保养」过滤。")
        }
    }

    // ---------- 1030 清洁月历 (本月打点) ----------
    private var careMarksSection: some View {
        let marks = BatteryCare.careMarks()
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        let streak = BatteryCare.careStreakMonths
        return Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: 4) {
                    ForEach(1...max(days, 1), id: \.self) { d in
                        let key = Milestones.monthKey() + String(format: "-%02d", d)
                        Circle()
                            .fill(marks[key] == true ? DS.Palette.ok : DS.Palette.surfaceAlt)
                            .overlay(Circle().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                            .frame(width: 11, height: 11)
                    }
                }
                Text(streak > 0 ? "已连续 \(streak) 个月有保养" : "本月还没打点 — 完成保养后点亮")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("本月保养日历, \(streak > 0 ? "已连续 \(streak) 个月有保养" : "本月还未保养")")
        } header: {
            Text("清洁月历")
        } footer: {
            Text("完成保养即在月历打点; 连续 3 个月点亮「爱洁之家」徽章。")
        }
    }

    // ---------- 1028 保养历史过滤 (1014 事件) ----------
    private var historySection: some View {
        let all = BatteryCare.events(mac)
        return Section {
            if all.isEmpty {
                Text("还没有保养或换电记录。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
            }
            ForEach(Array(all.prefix(5).enumerated()), id: \.offset) { _, e in
                HStack(spacing: DS.Space.s) {
                    Image(systemName: e.kind == "battery" ? "battery.100" : "checkmark.seal")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .foregroundStyle(e.kind == "battery" ? DS.Palette.ok : DS.Palette.accentText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(e.kind == "battery" ? "更换电池" : "保养完成")
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Text(e.note + " · " + daysAgoText(e.ts))
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if !all.isEmpty {
                Button {
                    app.pendingRecordsFilter = "__care"
                    app.tabSelection = 2
                } label: {
                    Label("到记录页查看全部 (保养过滤)", systemImage: "line.3.horizontal.decrease.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        } header: {
            Text("保养历史")
        }
    }

    // ---------- 116/118 换电 + 1012 年度提醒 ----------
    private var swapSection: some View {
        Section {
            NavigationLink { BatterySwapGuideView() } label: {
                Label("换电池图文指引", systemImage: "battery.100")
                    .frame(minHeight: DS.Hit.min)
            }
            LabeledRow("上次换电",
                       meta.batteryChangedAt > 0 ? daysAgoText(meta.batteryChangedAt * 1000) : "未记录 (见电池档案)")
            // 1034 充电记录: 可充电型号记充电日期与时长 (纯本机台账, 与协议无关)
            Button { markCharge() } label: {
                LabeledRow("上次充电 (可充电型号)",
                           care.chargeAt > 0
                               ? daysAgoText(care.chargeAt) + (care.chargeLenMin > 0 ? " · \(care.chargeLenMin) 分钟" : "")
                               : "未记录")
            }
            .foregroundStyle(DS.Palette.text)
            Toggle("每年换电池提醒", isOn: $yearlyOn)
            if yearlyOn {
                DatePicker("提醒日期", selection: $yearlyDate, displayedComponents: .date)
            }
        } header: {
            Text("换电关怀")
        } footer: {
            Text("年度提醒在选定日期上午 10 点送达 (本地通知, 白天送达)。")
        }
    }

    // ---------- 1025 应急钥匙半年检 ----------
    private var ekeySection: some View {
        Section {
            Toggle("应急钥匙半年检提醒", isOn: $ekeyOn)
                .onChange(of: ekeyOn) { _, _ in saveEkey() }
            LabeledRow("上次打卡", care.ekeyCheckAt > 0 ? daysAgoText(care.ekeyCheckAt) : "未打卡")
            Button {
                var s = BatteryCare.care(mac)
                s.ekeyCheckAt = Date().timeIntervalSince1970 * 1000
                BatteryCare.saveCare(mac, s)
                care = s
                DS.Haptics.tick.impactOccurred()
                app.showToast("已打卡 — 下次半年检会重新起算")
            } label: {
                Label("确认应急钥匙还在 · 打卡", systemImage: "key.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Text("应急钥匙")
        } footer: {
            Text("像消防演练一样每半年确认一次应急钥匙的位置与可用性。")
        }
    }

    // ---------- 1024 潮湿位 + 1026 低温季 ----------
    private var environmentSection: some View {
        let place = meta.place
        let damp = ["浴室", "户外", "院", "阳台", "天台"].contains { place.contains($0) }
        return Section {
            if damp {
                Label("场所「\(place)」属湿区 — 梅雨季 (6–7 月) 每周提醒防潮", systemImage: "humidity")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("在锁档案的「场所副标题」里写上浴室/户外等字样, 即可获得季节防潮提醒。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if BatteryCare.isColdSeason {
                Label("低温季 (11–3 月): 电池衰减加快, 电量偏低时建议提前整组换新。", systemImage: "thermometer.snowflake")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("环境关怀")
        }
    }
}

// ================= 1015 保养五项清单 =================
struct CareChecklistView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void = {}
    @State private var checks = [false, false, false, false, false]
    private let items: [(icon: String, label: String)] = [
        ("gearshape.2", "滑轨与把手顺滑"),
        ("lock.rotation", "锁舌伸缩顺畅"),
        ("battery.100", "电池触点无锈蚀"),
        ("finger.print", "指纹头清洁"),
        ("key.fill", "应急钥匙位置确认"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                        Button { checks[i].toggle() } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(checks[i] ? DS.Palette.ok : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                                Image(systemName: it.icon)
                                    .font(.system(size: DS.Icon.sm, weight: .medium))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(it.label)
                                    .font(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(it.label)
                        .accessibilityAddTraits(checks[i] ? [.isSelected] : [])
                    }
                } header: {
                    Text("五项清单")
                } footer: {
                    Text("逐项确认后才能完成保养 — 汽车保养手册的严谨, 用在门上一样合适。")
                }
                Section {
                    BusyButton(title: "完成保养",
                               systemImage: "checkmark.seal",
                               isBusy: false,
                               disabled: !checks.allSatisfy({ $0 })) {
                        complete()
                    }
                }
            }
            .navigationTitle("锁体保养")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    private func complete() {
        let mac = app.current?.mac ?? ""
        var s = BatteryCare.care(mac)
        s.lastCareAt = Date().timeIntervalSince1970 * 1000
        BatteryCare.saveCare(mac, s)
        BatteryCare.markCareToday()                      // 1030 月历打点
        BatteryCare.addEvent(mac, kind: "care", note: "五项保养完成")   // 1014
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("保养已记录, 90 天周期重新起算")
        app.evaluateAchievements()                       // 1030 爱洁之家徽章结算
        onDone()
        dismiss()
    }
}

// ================= 116/1033 换电图文引导 + 118 换电复位 =================
// 1033 换电池向导与 116 是同一落点: 分步图文 (开盖-换电池-校时), 完成写记录
// (BatteryCare.recordBatterySwap 已含 1014 事件 + 采样基线), 故不单列向导页, 仅此处备案。
struct BatterySwapGuideView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private var mac: String { app.current?.mac ?? "" }
    private var modelHint: String {
        let m = LockArchive.meta(mac).batteryModel
        return m.isEmpty ? "型号见锁信息名片-电池档案" : "已记型号: \(m)"
    }
    private var steps: [(icon: String, title: String, detail: String)] {
        [
            ("battery.100", "备好同型号新电池", modelHint),
            ("wrench.and.screwdriver", "拆下电池盖板", "一般在室内面板, 不需要拆卸整锁"),
            ("arrow.triangle.2.circlepath", "整组换新", "不要新旧电池混用, 触点对准弹簧"),
            ("clock.arrow.circlepath", "换电后校准门锁时间", "临时密码与时间窗凭证依赖锁钟"),
            ("checkmark.seal", "点下方「已换新」复位", "基线与低电提醒一并重置"),
        ]
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.onAccent)
                            .frame(width: 22, height: 22)
                            .background(DS.Palette.accent, in: Circle())
                            .accessibilityHidden(true)
                        Image(systemName: s.icon)
                            .font(.system(size: DS.Icon.md, weight: .medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(s.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Palette.text)
                            Text(s.detail)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, DS.Space.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("第 \(i + 1) 步: \(s.title), \(s.detail)")
                }
            } header: {
                Text("换电步骤")
            } footer: {
                Text("全程只动电池 — 不需要重置门锁, 也不需要重新配网。")
            }
            Section {
                BusyButton(title: "已换新", systemImage: "checkmark", isBusy: false) { swap() }
                NavigationLink { SyncTimeView() } label: {
                    Label("去校准门锁时间", systemImage: "clock.arrow.circlepath")
                        .frame(minHeight: DS.Hit.min)
                }
            } footer: {
                Text("「已换新」会写入换电记录、复位低电提醒武装位, 并在电池档案记下今天。")
            }
        }
        .navigationTitle("换电指引")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    /// 118 换电复位基线: 电池档案 + 采样基线 + 通知武装位 + 1014 事件, 一次到位
    private func swap() {
        var m = LockArchive.meta(mac)
        m.batteryChangedAt = Date().timeIntervalSince1970
        LockArchive.save(mac, m)
        BatteryCare.recordBatterySwap(mac)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("已换新 · 基线与提醒已复位")
        app.evaluateAchievements()   // 1039 续航管家徽章结算
        dismiss()
    }
}

// ================= 设置-提醒 (287 阈值 / 1031 免扰 / 1038 白天送达 / 146 升级提醒) =================
struct MaintSettingsView: View {
    var body: some View {
        Form {
            Section {
                Picker("低电提醒阈值", selection: Binding(
                    get: { CareSchedule.battThreshold },
                    set: { DB.store.set("kf_batt_threshold", $0) })) {
                    Text("10%").tag(10)
                    Text("15%").tag(15)
                    Text("20%").tag(20)
                }
                .pickerStyle(.menu)
            } header: {
                Text("低电")
            } footer: {
                Text("低于阈值时设备页横幅提醒; 电量 ≤20% 另有「该喂电了」本地通知, ≤10% 升级为告急。")
            }
            Section {
                Toggle("夜间免扰 (22–8 点)", isOn: Binding(
                    get: { CareSchedule.quietOn },
                    set: { DB.store.set("kf_quiet_night", $0) }))
            } header: {
                Text("免扰")
            } footer: {
                Text("开启后免扰时段不弹通知 (App 内横幅不受影响); 保养/换电/半年检等定时提醒统一在上午 10 点送达。")
            }
            Section {
                Toggle("本地固件比锁内新时提醒", isOn: Binding(
                    get: { CareSchedule.fwRemindOn },
                    set: { DB.store.set("kf_fw_remind", $0) }))
            } header: {
                Text("固件")
            } footer: {
                Text("每次打开 App 时对照本机固件清单与锁内版本, 有更新才提醒 (全离线, 不访问任何服务器)。")
            }
        }
        .navigationTitle("维护提醒")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}
