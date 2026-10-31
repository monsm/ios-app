// DefendScreen.swift —— 布防（门 · 布防）
//
// 这屏干什么：布防是 cmd25 的三个自由度（control + start + end），本页把它收成三档：
// 撤防 / 不定期 / 每日时段。布防期间「靠近自动开锁」被一票否决，这是本页要说的唯一后果。
// 数据从哪来：本机布防记录（Engine 未接，本页用可替换的 DefendConfig）。
// 主动作：那一个「执行布防 / 撤防」按钮；时段用两个步进器改，不是摆设。
import SwiftUI

struct DefendScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// control 三值：0 撤防 / 1 不定期 / 2 每日时段（协议口径，不是视觉分档）。
    private enum Mode: Int, CaseIterable, Identifiable {
        case off = 0
        case once = 1
        case period = 2

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .off: return "撤防"
            case .once: return "不定期布防"
            case .period: return "每日时段布防"
            }
        }

        var note: String {
            switch self {
            case .off: return "门锁退出布防，自动开锁恢复正常。"
            case .once: return "布防到你手动撤防为止。适合今天出门、晚上回来。"
            case .period: return "每天在固定时段内布防，时段外正常开锁。"
            }
        }
    }

    private struct DefendConfig: Equatable {
        var control: Int
        var startMinute: Int
        var endMinute: Int
        var updatedAt: Int64?
    }

    @State private var config: DefendConfig?
    @State private var mode: Mode = .off
    @State private var startMinute = 22 * 60
    @State private var endMinute = 7 * 60
    @State private var busy = false
    @State private var askConfirm = false
    @State private var outcome: String?

    /// 时段步进器的一档 = 15 分钟（96 档覆盖一天）。
    private static let minuteStep = 15

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if app.lock == nil {
                    noLockPanel
                } else {
                    statusPanel
                    modePanel
                    if mode == .period {
                        periodPanel
                    }
                    actionPanel
                    effectPanel
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("布防")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .alert(mode == .off ? "确认撤防？" : "确认布防？", isPresented: $askConfirm) {
            Button("取消") { }
            Button(mode == .off ? "撤防" : "布防") { Task { await apply() } }
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("布防")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    // 状态行最多两行：宁可换行，不要截断或缩字（缩字会把 13pt 压到 10pt，低于可读下限）
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, V.S.pageGutter)
    }

    private var savedMode: Mode {
        Mode(rawValue: config?.control ?? 0) ?? .off
    }

    private var isActiveNow: Bool {
        guard let config else { return false }
        switch savedMode {
        case .off: return false
        case .once: return true
        case .period: return inWindow(config.startMinute, config.endMinute, nowMinute())
        }
    }

    private var headerTone: Tone {
        guard app.lock != nil else { return .neutral }
        return isActiveNow ? .attention : .neutral
    }

    private var headerWord: String {
        guard app.lock != nil else { return "无锁" }
        return isActiveNow ? "布防中" : "未布防"
    }

    private var headerText: String {
        guard let lock = app.lock else { return "还没有门锁可以布防" }
        if isActiveNow { return "\(lock.name) · 此刻靠近不会自动开门" }
        return "\(lock.name) · 此刻自动开锁照常"
    }

    // MARK: 现状（这一屏的主角：布防状态本身）

    private var statusPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "当前布防", trailing: "cmd25")
                HStack(alignment: .firstTextBaseline, spacing: V.S.gapMS) {
                    Text(savedMode.title)
                        .font(V.F.display26)
                        .foregroundStyle(V.C.text1)
                    Spacer(minLength: V.S.gapS)
                    VStateDot(tone: isActiveNow ? .attention : .neutral,
                             word: isActiveNow ? "布防中" : "未布防")
                }
                hairline
                VReadingGrid(items: [
                    .init(label: "方式", value: savedMode.title),
                    .init(label: "时段", value: savedMode == .period
                          ? "\(clockLabel(config?.startMinute ?? startMinute)) – \(clockLabel(config?.endMinute ?? endMinute))"
                          : "—"),
                    .init(label: "此刻", value: isActiveNow ? "布防内" : "布防外",
                          tint: isActiveNow ? V.C.warning : V.C.text1),
                    .init(label: "上次改动", value: config?.updatedAt.map { TimeFormat.clock($0) } ?? "—",
                          tint: V.C.text2),
                ], columns: 2)
                .padding(.top, V.S.gapXS)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 三档（真交互：点了就换选中态，并决定下面的表单出不出）

    private var modePanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "布防方式", trailing: "三选一")
                VStack(spacing: 0) {
                    ForEach(Array(Mode.allCases.enumerated()), id: \.element.id) { index, m in
                        if index > 0 { hairline }
                        modeRow(m)
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func modeRow(_ m: Mode) -> some View {
        let on = mode == m
        return Button {
            mode = m
            outcome = nil
        } label: {
            HStack(alignment: .top, spacing: V.S.gapMS) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon18)
                    .foregroundStyle(on ? V.C.text1 : V.C.text3)
                    .frame(width: V.Icon.l, alignment: .leading)
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(m.title)
                        .font(V.F.bodyStrong)
                        .foregroundStyle(V.C.text1)
                    Text(m.note)
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.title)：\(m.note)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 时段（两个步进器，改了就真改；校验不通过就说清）

    private var periodPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "每日时段", trailing: "每 15 分钟一档")
                stepRow(title: "开始", minutes: $startMinute)
                hairline
                stepRow(title: "结束", minutes: $endMinute)
                hairline
                Text(periodNote)
                    .font(V.F.footnote)
                    .foregroundStyle(periodValid ? V.C.text2 : V.C.critical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func stepRow(title: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: V.S.gapMS) {
            Text(title)
                .font(V.F.body)
                .foregroundStyle(V.C.text2)
            Spacer(minLength: V.S.gapS)
            VReading(value: clockLabel(minutes.wrappedValue), font: V.F.number17)
            stepButton("minus", label: "\(title)提前 15 分钟") {
                minutes.wrappedValue = wrapMinutes(minutes.wrappedValue - Self.minuteStep)
            }
            stepButton("plus", label: "\(title)推迟 15 分钟") {
                minutes.wrappedValue = wrapMinutes(minutes.wrappedValue + Self.minuteStep)
            }
        }
        .frame(minHeight: V.Hit.min)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(V.F.icon15Semibold)
                .foregroundStyle(V.C.text1)
                .frame(width: V.Hit.min, height: V.Hit.min)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private var periodValid: Bool {
        startMinute != endMinute
    }

    private var periodNote: String {
        if !periodValid {
            return "开始与结束不能是同一时刻 —— 那等于全天布防或全天不布防，协议里表达不出你的意思。"
        }
        if endMinute < startMinute {
            return "跨午夜时段：\(clockLabel(startMinute)) 到次日 \(clockLabel(endMinute))。这段时间里靠近门锁不会自动开门。"
        }
        return "时段内进入布防，时段外正常开锁。跨午夜指开始晚于结束。"
    }

    // MARK: 主动作

    private var actionPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "下发", trailing: "cmd25")
                if busy {
                    VBusyRow(text: mode == .off ? "正在撤防…" : "正在布防…")
                } else {
                    VActionButton(
                        title: actionTitle,
                        systemImage: "shield.lefthalf.filled",
                        busy: false
                    ) {
                        askConfirm = true
                    }
                    .opacity(canApply ? 1 : 0.5)
                    .disabled(!canApply)
                }
                if !canApply {
                    Text("先把时段设成两个不同的时刻，再执行。")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                }
                if let outcome {
                    VStatusLine(tone: .ok, text: outcome)
                }
                Text("rc=0 只说明锁收了命令。锁端状态帧不带布防字段，所以这里不宣称「锁已进入布防」，只记本机与回执。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var canApply: Bool {
        mode == .period ? periodValid : true
    }

    private var actionTitle: String {
        switch mode {
        case .off: return "执行撤防"
        case .once: return "执行布防"
        case .period: return "保存时段并布防"
        }
    }

    private var confirmMessage: String {
        switch mode {
        case .off:
            return "撤防后门锁恢复正常开锁，靠近自动开锁也会恢复。"
        case .once:
            return "门锁进入不定期布防，直到你手动撤防。布防期间靠近门锁不会自动开门。"
        case .period:
            return "时段 \(clockLabel(startMinute)) – \(clockLabel(endMinute)) 内布防；时段内自动开锁会被一票否决。"
        }
    }

    // MARK: 后果（把布防的语义写清：它否决的是自动开锁，不是手动开锁）

    private var effectPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "布防期间会发生什么")
                effectLine("靠近自动开锁：被否决。站在门口不会自己开 —— 这正是布防的意义。")
                effectLine("手动开锁：照常。你自己按刻度盘开门不受影响，否则人就被锁在门外了。")
                effectLine("布防不能远程设置，也不能远程解除：必须站在门锁旁边做。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func effectLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: V.S.gapS) {
            VStateDot(tone: .neutral, word: "须知")
            Text(text)
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 空态

    private var noLockPanel: some View {
        VCard {
            VEmptyState(
                title: "还没有门锁可以布防",
                message: "布防是写给门锁的：先添加门锁，再回这一页设时段。不是所有型号都支持布防，网关一律不支持。",
                actionTitle: "添加门锁",
                systemImage: "shield.lefthalf.filled"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 读写

    private func load() {
        guard config == nil else { return }
        guard let kc = app.currentKeychain else { return }
        if let c = DB.defend(kc.mac) {
            config = DefendConfig(control: c.control,
                                  startMinute: DefendKit.secFromProto(c.startSec) / 60,
                                  endMinute: DefendKit.secFromProto(c.endSec) / 60,
                                  updatedAt: Int64(c.at))
            mode = Mode(rawValue: c.control) ?? .off
        } else {
            config = DefendConfig(control: 0, startMinute: 22 * 60, endMinute: 7 * 60, updatedAt: nil)
            mode = .off
        }
    }

    @MainActor
    private func apply() async {
        guard !busy, canApply, let kc = app.currentKeychain else { return }
        busy = true
        outcome = nil
        let dm = DefendMode(rawValue: mode.rawValue) ?? .off
        let startSec = mode == .period ? startMinute * 60 : 0
        let endSec = mode == .period ? endMinute * 60 : 0
        do {
            // 真链路：cmd25 下发（半秒刻度由 DefendKit 换算）→ 成功才写本地 kf_defend_。
            try await DefendService.apply(host: app, mode: dm, startSec: startSec, endSec: endSec)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            config = DefendConfig(control: mode.rawValue,
                                  startMinute: startMinute,
                                  endMinute: endMinute,
                                  updatedAt: now)
            outcome = mode == .off ? "已撤防（锁端回执成功）" : "已布防（锁端回执成功）"
            _ = kc
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        busy = false
    }

    // MARK: 工具

    private func clockLabel(_ minutes: Int) -> String {
        let m = wrapMinutes(minutes)
        let hh = m / 60
        let mm = m % 60
        return "\(pad2(hh)):\(pad2(mm))"
    }

    private func wrapMinutes(_ minutes: Int) -> Int {
        let span = 24 * 60
        let v = minutes % span
        return v < 0 ? v + span : v
    }

    private func nowMinute(_ date: Date = Date()) -> Int {
        let comps = TimeFormat.calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// 时段判定：start == end 按全天布防（fail-closed，不退化成空集）；跨午夜取两段。
    private func inWindow(_ start: Int, _ end: Int, _ now: Int) -> Bool {
        if start == end { return true }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }

    private func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private var hairline: some View {
        Rectangle()
            .fill(V.C.hairline)
            .frame(height: V.S.hair)
    }
}
