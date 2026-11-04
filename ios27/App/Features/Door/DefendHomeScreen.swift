// DefendHomeScreen.swift —— 布防（V8 设计语言）
//
// 与 DefendScreen 的能力对齐：布防是三个自由度（control + start + end），本页把它收成三档：
// 撤防 / 不定期 / 每日时段。布防期间「靠近自动开锁」被一票否决，这是本页要说的唯一后果。
// 只改渲染层：下发仍走 DefendService.apply，本地记忆仍落 kf_defend_<mac>。
//
// 与旧页的刻意差异：
//   ① 空壳模式不显示也不写入布防配置（app.currentKeychain 在空壳下仍返回真锁，
//      DB.defend 读的是真实配置，必须显式挡住）。
//   ② 只读试验模式明确禁止下发，不再让用户点完才看到引擎拦下。
import SwiftUI

struct DefendHomeScreen: View {
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

    private struct DefendConfigVM: Equatable {
        var control: Int
        var startMinute: Int
        var endMinute: Int
        var updatedAt: Int64?
    }

    @State private var config: DefendConfigVM?
    @State private var mode: Mode = .off
    @State private var startMinute = 22 * 60
    @State private var endMinute = 7 * 60
    @State private var busy = false
    @State private var askConfirm = false
    @State private var outcome: String?
    @State private var outcomeOK = true

    /// 时段步进器的一档 = 15 分钟（96 档覆盖一天）。
    private static let minuteStep = 15

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

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

    private var judgement: String {
        if decoyed { return "空壳模式不显示布防" }
        guard app.lock != nil else { return "还没有门锁可以布防" }
        if savedMode == .off { return "当前未布防" }
        return isActiveNow ? "当前布防中 · " + savedMode.title : "当前布防外 · " + savedMode.title
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。布防配置不显示，也不提供下发。"
        }
        guard let lock = app.lock else {
            return "布防是写给门锁的：先添加门锁，再回这一页设时段。"
        }
        return lock.name + " · 布防期间靠近门锁不会自动开门，手动开锁照常。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "还没有门锁可以布防",
                    reason: "布防是写给门锁的：先添加门锁，再回这一页设时段。不是所有型号都支持布防，网关一律不支持。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                statusCard
                modeCard
                if mode == .period {
                    periodCard
                }
                actionCard
                effectCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .v8Confirm(
            isPresented: $askConfirm,
            title: mode == .off ? "确认撤防？" : "确认布防？",
            consequence: confirmMessage,
            confirmTitle: mode == .off ? "撤防" : "布防",
            isDestructive: mode != .off
        ) {
            Task { await apply() }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(isActiveNow ? 1 : 0.02, isActiveNow ? V8.C.warn : V8.C.ink4), label: "状态", value: isActiveNow ? "布防中" : "未布防")
                VChip2(icon: .glyph("shield.lefthalf.filled"), label: "方式", value: savedMode.title)
                VChip2(icon: .glyph("clock"), label: "时段", value: periodChipText)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var periodChipText: String {
        guard savedMode == .period else { return "全天" }
        let start = clockLabel(config?.startMinute ?? startMinute)
        let end = clockLabel(config?.endMinute ?? endMinute)
        return start + "–" + end
    }

    // MARK: - 当前布防

    private var statusCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当前布防", statement: savedMode.title, trailing: "锁端策略")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if savedMode == .off {
                VDataRow(tag: "此刻", tagTint: V8.C.ink4, title: "自动开锁照常", value: "")
                    .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    VDataRow(tag: "此刻", tagTint: isActiveNow ? V8.C.warn : V8.C.ink4, title: isActiveNow ? "布防内" : "布防外", value: "")
                    VDotRule()
                    VDataRow(tag: "时段", tagTint: V8.C.ink4, title: savedMode == .period ? periodChipText : "全天", value: "")
                    VDotRule()
                    VDataRow(tag: "改动", tagTint: V8.C.ink4, title: "上次改动", value: config?.updatedAt.map { TimeDisplay.clock($0) } ?? "—")
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 布防方式

    private var modeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "布防方式", statement: "三选一")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(Mode.allCases.enumerated()), id: \.element.id) { index, m in
                    if index > 0 { VDivider2() }
                    modeRow(m)
                }
            }
        }
    }

    private func modeRow(_ m: Mode) -> some View {
        let on = mode == m
        return Button {
            mode = m
            outcome = nil
        } label: {
            HStack(alignment: .top, spacing: V8.S.gapM) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(V8.T.chipValue)
                    .foregroundStyle(on ? V8.C.accent : V8.C.ink4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text(m.title)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(m.note)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.title + "：" + m.note)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 每日时段

    private var periodCard: some View {
        VCard2 {
            VCardHead(eyebrow: "每日时段", statement: "每 15 分钟一档")
            VDivider2()
                .padding(.top, V8.S.gapM)
            stepRow(title: "开始", minutes: $startMinute)
            VDivider2()
            stepRow(title: "结束", minutes: $endMinute)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            Text(periodNote)
                .font(V8.T.footnote)
                .foregroundStyle(periodValid ? V8.C.ink3 : V8.C.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(title: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: V8.S.gapM) {
            Text(title)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
            Spacer(minLength: V8.S.gapS)
            Text(clockLabel(minutes.wrappedValue))
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
                .monospacedDigit()
            stepButton("minus", label: title + "提前 15 分钟") {
                minutes.wrappedValue = wrapMinutes(minutes.wrappedValue - Self.minuteStep)
            }
            stepButton("plus", label: title + "推迟 15 分钟") {
                minutes.wrappedValue = wrapMinutes(minutes.wrappedValue + Self.minuteStep)
            }
        }
        .frame(minHeight: V8.H.min)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(V8.T.chipValue)
                .foregroundStyle(V8.C.ink1)
                .frame(minWidth: V8.H.min, minHeight: V8.H.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var periodValid: Bool {
        startMinute != endMinute
    }

    private var periodNote: String {
        if !periodValid {
            return "开始与结束相同 —— 锁端会把它当成全天布防。要设成某个时段，请把结束时间挪开一档。"
        }
        if endMinute < startMinute {
            return "跨午夜时段：" + clockLabel(startMinute) + " 到次日 " + clockLabel(endMinute) + "。这段时间里靠近门锁不会自动开门。"
        }
        return "时段内进入布防，时段外正常开锁。跨午夜指开始晚于结束。"
    }

    // MARK: - 下发

    private var actionCard: some View {
        VCard2 {
            VCardHead(eyebrow: "下发", statement: readOnly ? "只读试验模式 · 不可写" : "立即生效")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if busy {
                VBusy(text: mode == .off ? "正在撤防…" : "正在布防…")
                    .padding(.top, V8.S.gapM)
            } else {
                Button {
                    askConfirm = true
                } label: {
                    Text(actionTitle)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(!canApply || readOnly)
                .opacity((canApply && !readOnly) ? 1 : 0.45)
                .padding(.top, V8.S.gapM)
            }
            if !canApply {
                Text("先把时段设成两个不同的时刻，再执行。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
            }
            if readOnly {
                Text("只读试验模式已开启：布防下发会被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let outcome {
                if outcomeOK {
                    Text(outcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ok)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VFailure(
                        what: "布防没有下发成功",
                        why: outcome,
                        next: "确认手机在门锁旁边、蓝牙已开；命令只回「收到」不代表已生效，回读后再判断。"
                    ) {
                        askConfirm = true
                    }
                    .padding(.top, V8.S.gapS)
                }
            }
            Text("锁只回了「收到命令」，并没有回报当前的布防状态 —— 所以这里不会说「已进入布防」，只记录本机状态与这次回执。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            return "撤防后门锁恢复正常开锁，靠近自动开锁也会恢复。随时可以重新布防 —— 可以撤销。"
        case .once:
            return "门锁进入不定期布防，直到你手动撤防。布防期间靠近门锁不会自动开门；在本页撤防即可恢复。"
        case .period:
            return "时段 " + clockLabel(startMinute) + " – " + clockLabel(endMinute) + " 内布防；时段内自动开锁会被一票否决。随时可以在本页撤防恢复自动开锁。"
        }
    }

    // MARK: - 后果

    private var effectCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "布防期间会发生什么", statement: "否决自动开锁，不否决手动开锁")
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("· 靠近自动开锁：被否决。站在门口不会自己开 —— 这正是布防的意义。")
                Text("· 手动开锁：照常。你自己按刻度盘开门不受影响，否则人就被锁在门外了。")
                Text("· 布防不能远程设置，也不能远程解除：必须站在门锁旁边做。")
            }
            .font(V8.T.footnote)
            .foregroundStyle(V8.C.ink3)
            .padding(.top, V8.S.gapM)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "布防", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，布防配置不显示，也不提供下发。布防会写锁端策略，这一步在空壳里停掉。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 读写

    private func load() {
        guard config == nil, !decoyed else { return }
        guard let kc = app.currentKeychain else { return }
        if let c = DB.defend(kc.mac) {
            config = DefendConfigVM(control: c.control,
                                    startMinute: DefendKit.secFromProto(c.startSec) / 60,
                                    endMinute: DefendKit.secFromProto(c.endSec) / 60,
                                    updatedAt: Int64(c.at))
            mode = Mode(rawValue: c.control) ?? .off
        } else {
            config = DefendConfigVM(control: 0, startMinute: 22 * 60, endMinute: 7 * 60, updatedAt: nil)
            mode = .off
        }
    }

    @MainActor
    private func apply() async {
        guard !busy, canApply, !decoyed, !readOnly, let kc = app.currentKeychain else { return }
        busy = true
        outcome = nil
        outcomeOK = true
        let dm = DefendMode(rawValue: mode.rawValue) ?? .off
        let startSec = mode == .period ? startMinute * 60 : 0
        let endSec = mode == .period ? endMinute * 60 : 0
        do {
            // 真链路：下发布防 → 成功才写本地 kf_defend_。
            try await DefendService.apply(host: app, mode: dm, startSec: startSec, endSec: endSec)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            config = DefendConfigVM(control: mode.rawValue,
                                    startMinute: startMinute,
                                    endMinute: endMinute,
                                    updatedAt: now)
            outcome = mode == .off ? "已撤防（锁端回执成功）" : "已布防（锁端回执成功）"
            outcomeOK = true
            _ = kc
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            outcomeOK = false
        }
        busy = false
    }

    // MARK: - 工具

    private func clockLabel(_ minutes: Int) -> String {
        let m = wrapMinutes(minutes)
        let hh = m / 60
        let mm = m % 60
        return DF.pad2(hh) + ":" + DF.pad2(mm)
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
}
