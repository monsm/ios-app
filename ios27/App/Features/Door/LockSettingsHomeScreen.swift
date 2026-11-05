// LockSettingsHomeScreen.swift —— 锁设置（V8 设计语言 · 02 分册 IA 归并后的宿主页）
//
// 本页是 §3.1 归并的宿主：锁端策略全在这。吸收的段与来源：
//   ·「这台锁」读数段（← lockStatus / LockStatusHomeScreen）：电量 / 信号 / 本机凭证 / 固件 / 型号 / 链路 /
//     上次开锁 + 安全模式 / 静音两枚即点即写开关 + 重读。
//   ·「锁钟」段（← syncTime / SyncTimeHomeScreen）：锁内 / 手机时间对照、偏差 > 2 秒判定、下发 + 回读复核、三条须知。
//   ·「布防」段（← defend / DefendHomeScreen）：三档、isActiveNow、15 分钟步进、下发 + 诚实边界文案。
//   ·「防尾随」段（← tailgate / TailgateHomeScreen）：2–6 秒档位、型号/固件门禁、下发。
//   ·「安全模式」段（← safeMode / SafeModeHomeScreen）：A / B / C 说明、切换 + 回读确认、放宽二次确认。
// 本体能力不变：动态密码开通/关闭、静音、这台锁只读读数、清空全部密码（键入「清空」+ 二次确认）。
// 能力守恒：上述来源页的全部真链路（app.setSafeMode / app.setMuted / app.syncTime / app.refreshStatus /
// LockService.ensureConnected + setValidationMode + setAutoLock + getStatus、DefendService.apply、
// DB.saveSyncTime / DB.saveTailgate / DB.saveDefend 经服务落盘）逐条搬入，状态分支与文案因果原样保留。
import SwiftUI

struct LockSettingsHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var otpOn = false
    @State private var muted = false
    @State private var autoLock = 6
    @State private var busy = false
    @State private var outcome: String?
    /// 最近一次动作是成功还是失败 —— 决定 outcome 的语义色。
    @State private var outcomeIsFailure = false
    /// 读取失败单独一条：失败卡要说清「读锁失败」，不能把一次写入失败混进来。
    @State private var readError: String?
    /// 写入失败单独一条：失败卡要说清「设置没有生效」。
    @State private var actionError: String?
    @State private var clearConfirm = false
    @State private var clearTyped = ""
    @State private var tailgateLoaded = false

    // 「这台锁」段（← lockStatus）：策略开关的写入序列号与放宽确认。
    @State private var policyRev = 0
    @State private var confirmRelax = false

    // 「锁钟」段（← syncTime）。
    @State private var lockAt: Int64?
    @State private var syncBusy = false
    @State private var syncResult: SyncOutcome?
    @State private var lastSyncedAt: Int64?

    // 「布防」段（← defend）。
    @State private var defendConfig: DefendConfigVM?
    @State private var defendMode: DefendModeVM = .off
    @State private var startMinute = 22 * 60
    @State private var endMinute = 7 * 60
    @State private var defendBusy = false
    @State private var askDefendConfirm = false
    @State private var defendOutcome: String?
    @State private var defendOutcomeOK = true
    @State private var defendLoaded = false

    // 「防尾随」段（← tailgate）。
    @State private var tailgateSeconds = 6
    @State private var tailgateBusy = false
    @State private var tailgateOutcome: String?

    // 「安全模式」段（← safeMode）。
    @State private var safeBusy = false
    @State private var safeOutcome: String?

    private struct SyncOutcome: Equatable {
        let ok: Bool
        let text: String
    }

    private static let driftThreshold = 2
    /// 时段步进器的一档 = 15 分钟（96 档覆盖一天）。
    private static let minuteStep = 15

    /// 布防三档（与 DefendMode 同一 rawValue 口径）。
    private enum DefendModeVM: Int, CaseIterable, Identifiable {
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

    private var mac: String { app.lock?.id ?? "" }
    private var decoyed: Bool { DB.isDecoy }
    private var kc: Keychain? { app.currentKeychain }
    private var lock: LockSummary? { app.lock }
    private var readOnly: Bool { app.trialGuard }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不显示锁设置" }
        guard let lock = app.lock else { return "还没有门锁可设置" }
        return lock.name + " · " + (otpOn ? "动态码已开通" : "动态码已关闭")
    }

    private var lead: String? {
        if decoyed { return "空壳模式只隐藏、不改动：本页既不显示这把锁的策略，也不写入任何设置。退出空壳后才能改。" }
        if app.lock == nil { return nil }
        return "这一页改的都是锁端策略：写成功后回读确认，本机只留一份镜像。读数段在第一张卡，各段可展开收起。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed || app.lock == nil {
                EmptyView()
            } else {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                // 2026-11-05（对抗审查 · 设计冗余）：本页标题（judgement）已经是
                // 「还没有门锁可设置」，空态卡又用同一个标题 ⇒ 屏幕上同一个句子出现两次。
                // 空态标题改成动作导向，和标题分工：标题说状态，卡片说下一步。
                VEmpty(
                    title: "添加一把门锁",
                    reason: "锁设置改的是具体一把锁的锁端策略：先添加并配对门锁，再回这一页。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                if app.trialGuard { trialCard }
                if let actionError { actionErrorCard(actionError) }
                tempCodeCard
                thisLockCard
                clockSection
                safeModeSection
                tailgateSection
                defendSection
                dangerCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.currentMac) {
            // 2026-11-05（对抗审查）：原 .task 无 id —— 切换当前锁后不会重跑，
            // 而 tailgateLoaded / defendLoaded 守卫让防尾随与布防段还显示旧锁的档位。
            // 加 id 后换锁即重载；守卫的作用变成同一次载入内不重复读锁。
            await load()
            await readClock()
        }
        .onChange(of: app.currentMac) { _, _ in
            // 2026-11-05（对抗审查）：换锁清掉两个一次性守卫，让防尾随/布防段重载新锁的档位。
            tailgateLoaded = false
            defendLoaded = false
        }
        .v8Confirm(
            isPresented: $clearConfirm,
            title: "清空全部密码？",
            consequence: "会把锁里所有密码作废（指纹保留），本机密码台账同时清空。这一步不可撤销：清空后只能逐条重新添加。",
            confirmTitle: "清空密码",
            isDestructive: true
        ) {
            Task { await runClearPwd() }
        }
        .v8Confirm(
            isPresented: $confirmRelax,
            title: "放宽安全模式？",
            consequence: "放宽后一枚凭证就能单独开门，这是降低安全等级。之后可以随时切回双验，但放宽期间发生的开门无法撤回。",
            confirmTitle: "放宽",
            isDestructive: true
        ) {
            writeSafeMode(false)
        }
        .v8Confirm(
            isPresented: $askDefendConfirm,
            title: defendMode == .off ? "确认撤防？" : "确认布防？",
            consequence: defendConfirmMessage,
            confirmTitle: defendMode == .off ? "撤防" : "布防",
            isDestructive: defendMode != .off
        ) {
            Task { await applyDefend() }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("clock.badge.questionmark"), label: "动态密码", value: otpOn ? "已开通" : "已关闭")
                VChip2(icon: .ring(batteryFraction, batteryChipTint), label: "电量", value: batteryChipText)
                VChip2(icon: .glyph("lock.rotation"), label: "安全模式", value: safeModeText)
                VChip2(icon: .ring(isDefendActiveNow ? 1 : 0.02, isDefendActiveNow ? V8.C.warn : V8.C.ink4), label: "布防", value: isDefendActiveNow ? "布防中" : "未布防")
                VChip2(icon: .glyph("clock"), label: "锁钟", value: chipDriftText)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var chipDriftText: String {
        guard let t = status?.lockTime, t > 0 else { return "未读" }
        let dev = Int(t - ZKProtocol.nowProtoSeconds())
        if abs(dev) <= Self.driftThreshold { return "一致" }
        return (dev > 0 ? "+" : "") + String(dev) + "s"
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁设置", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这一页既不显示这把锁的策略与读数，也不写入任何设置 —— 否则一次误触就会把真实的锁端策略改掉。")
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

    private func actionErrorCard(_ text: String) -> some View {
        VFailure(
            what: "设置没有生效",
            why: text,
            next: "确认门锁在附近、蓝牙开着；改锁端设置必须连上锁。可以先「重新读取锁状态」看看链路，再重试。"
        )
    }

    // MARK: - 只读试验模式

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "已开启 · 写入类命令会被拦下")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("这一页的动态密码、静音、清空密码、布防、防尾随与安全模式切换都要下发到门锁，护栏会把它们拦下。本机读数照常可读。要改设置，先到「安全」页关掉只读试验模式。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 1 动态密码

    private var tempCodeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "动态密码", statement: otpOn ? "已开通 · 锁端会接受动态码" : "已关闭 · 动态码不会被锁接受")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("开通后，锁端按周期接受动态密码；关闭则所有动态码立即失效。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            toggleRow(
                "开通动态密码",
                // 2026-11-05（对抗审查 · 设计冗余）：这里原来与卡头 statement **逐字相同**，
                // 同一个开关状态在一张卡里说了两遍。副文改成说清机制（下发 + 回读确认），
                // 状态仍由卡头唯一承载。
                detail: "下发到锁端，回读确认后才算开通",
                isOn: Binding(
                    get: { otpOn },
                    set: { on in writeOtp(on) }
                )
            )
            .disabled(app.trialGuard)
            .opacity(app.trialGuard ? 0.45 : 1)
            if otpOn {
                VNavRow(title: "生成动态密码", detail: "按锁端周期变化的临时码") {
                    router.request(.dest(.zotp))
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 卡 2 这台锁 · 读数与策略（← lockStatus）

    private var thisLockCard: some View {
        VCard2 {
            VCardHead(eyebrow: "这台锁", statement: thisLockStatement, trailing: lock?.isConnected == true ? "已连接" : "未连接")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let lock {
                VStack(spacing: 0) {
                    VDataRow(tag: "电量", tagTint: batteryRowTint, title: "当前电量", value: batteryRowValue, unit: batteryRowUnit)
                    VDotRule()
                    VDataRow(tag: "信号", tagTint: signalTint, title: "链路信号", value: signalRowValue, unit: signalRowUnit)
                    VDotRule()
                    VDataRow(tag: "凭证", tagTint: V8.C.ink4, title: "本机凭证", value: String(lock.keyCount), unit: "枚")
                    VDotRule()
                    VDataRow(tag: "固件", tagTint: V8.C.ink4, title: "锁内固件", value: firmwareText)
                    VDotRule()
                    VDataRow(tag: "型号", tagTint: V8.C.ink4, title: "产品型号", value: lock.model)
                    VDotRule()
                    VDataRow(tag: "链路", tagTint: V8.C.ink4, title: "连接方式", value: lock.isConnected ? "蓝牙直连" : "未建立")
                    VDotRule()
                    VDataRow(tag: "开锁", tagTint: V8.C.ink4, title: "上次开锁", value: lastOpenText)
                    VDotRule()
                    VDataRow(tag: "Boot", tagTint: V8.C.ink4, title: bootText, value: "")
                    VDotRule()
                    VDataRow(tag: "键盘", tagTint: V8.C.ink4, title: keyboardText, value: "")
                    VDotRule()
                    VDataRow(tag: "密码容量", tagTint: V8.C.ink4, title: pwdCapacityText, value: "")
                    VDotRule()
                    VDataRow(tag: "指纹容量", tagTint: V8.C.ink4, title: fpCapacityText, value: "")
                }
                .padding(.top, V8.S.gapS)
                Text("信号 0 表示还没测过，不代表信号差；电量未读到时不显示数字。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                if busy {
                    VBusy(text: "正在下发…")
                        .padding(.top, V8.S.gapM)
                } else if let readError {
                    VFailure(
                        what: "锁实况没读回来",
                        why: readError,
                        next: "走近门锁、确认手机蓝牙已开，再点重试。"
                    ) {
                        reread()
                    }
                    .padding(.top, V8.S.gapM)
                } else if let outcome {
                    Text(outcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(outcomeIsFailure ? V8.C.danger : V8.C.ok)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                policySwitchRow(
                    title: "安全模式",
                    note: "A / B 模式决定验一次还是两次。只许变严；放宽要二次确认。",
                    isOn: lock.safeMode,
                    onWord: "开 · 双验",
                    offWord: "关 · 单验"
                ) { on in
                    if on { writeSafeMode(true) } else { confirmRelax = true }
                }
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                policySwitchRow(
                    title: "静音",
                    note: "锁端提示音关掉后，按键只给机械反馈，不发声。",
                    isOn: lock.muted,
                    onWord: "开 · 无声",
                    offWord: "关 · 有声"
                ) { on in
                    writeMuted(on)
                }
                HStack(spacing: V8.S.gapS) {
                    Text(readOnly ? "只读试验模式 · 写入被停用" : "开关改动会立即下发，回执成功才更新读数")
                        .font(V8.T.caption)
                        .foregroundStyle(readOnly ? V8.C.warn : V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        reread()
                    } label: {
                        Text("重读")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink1)
                            .frame(minHeight: V8.H.min)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重新读取锁实况")
                }
                .padding(.top, V8.S.gapXS)
            }
        }
    }

    private var thisLockStatement: String {
        guard let lock else { return "—" }
        if lock.battery < 0 { return "还没读到电量" }
        return "这一把锁的读数与策略"
    }

    private var batteryRowTint: Color {
        guard let lock, lock.battery >= 0 else { return V8.C.ink4 }
        return lock.battery <= 20 ? V8.C.warn : V8.C.ok
    }

    private var batteryRowValue: String {
        guard let lock else { return "—" }
        return lock.battery < 0 ? "未知" : String(lock.battery)
    }

    private var batteryRowUnit: String? {
        guard let lock else { return nil }
        return lock.battery < 0 ? nil : "%"
    }

    private var batteryFraction: Double {
        guard let lock, lock.battery >= 0 else { return 0.02 }
        return min(1, max(0.02, Double(lock.battery) / 100))
    }

    private var batteryChipTint: Color {
        batteryRowTint == V8.C.ink4 ? V8.C.ink4 : batteryRowTint
    }

    private var batteryChipText: String {
        guard let lock, lock.battery >= 0 else { return "未知" }
        return String(lock.battery) + "%"
    }

    private var signalTint: Color {
        guard let lock, lock.signal > 0 else { return V8.C.ink4 }
        return lock.signal == 1 ? V8.C.warn : V8.C.ok
    }

    private var signalRowValue: String {
        guard let lock else { return "—" }
        return lock.signal <= 0 ? "未测" : String(lock.signal)
    }

    private var signalRowUnit: String? {
        guard let lock else { return nil }
        return lock.signal <= 0 ? nil : "/ 4"
    }

    private var lastOpenText: String {
        guard let at = app.lastActionAt else { return "还没有开锁记录" }
        return TimeFormat.ago(at)
    }

    /// 带本地状态的政策开关：手指动作立刻反映，锁端写入结果回来后再覆盖。
    /// revision 变化（每次写入成功或失败）时重新按 isOn 校准 —— 写失败时开关要弹回去。
    private struct PolicyToggle: View {
        let isOn: Bool
        let onWord: String
        let offWord: String
        let write: (Bool) -> Void
        let revision: Int

        @State private var localOn = false

        var body: some View {
            Toggle("", isOn: $localOn)
                .labelsHidden()
                .tint(V8.C.accent)
                .accessibilityValue(localOn ? onWord : offWord)
                .onChange(of: localOn) { _, new in
                    if new != isOn { write(new) }
                }
                .onChange(of: isOn) { _, new in localOn = new }
                .onChange(of: revision) { _, _ in localOn = isOn }
                .onAppear { localOn = isOn }
        }
    }

    private func policySwitchRow(
        title: String,
        note: String,
        isOn: Bool,
        onWord: String,
        offWord: String,
        write: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: V8.S.gapM) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Text(note)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? onWord : offWord)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
            }
            Spacer(minLength: V8.S.gapS)
            PolicyToggle(isOn: isOn, onWord: onWord, offWord: offWord, write: write, revision: policyRev)
                .accessibilityLabel(title)
                .disabled(readOnly)
                .opacity(readOnly ? 0.55 : 1)
        }
        .frame(minHeight: V8.H.min)
    }

    // MARK: - 段 3 锁钟（← syncTime）

    private var clockDrift: Int? {
        guard let lockAt else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return Int((now - lockAt) / 1000)
    }

    private var clockSection: some View {
        VCard2 {
            VCardHead(eyebrow: "锁钟", statement: clockStatement, trailing: "本机 / 锁端")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "锁内时间", value: lockAt.map { TimeDisplay.clock($0) } ?? "—"),
                .init(label: "手机时间", value: TimeDisplay.clock(Int64(Date().timeIntervalSince1970 * 1000)))
            ])
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VDataRow(tag: "偏差", tagTint: clockDriftTint, title: clockDrift.map { $0 == 0 ? "0" : (($0 > 0 ? "+" : "") + String($0)) } ?? "—", value: "", unit: clockDrift == nil ? nil : "秒")
            Text(clockDriftNote)
                .font(V8.T.footnote)
                .foregroundStyle(clockDrift == nil ? V8.C.ink3 : clockDriftTint)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if let lastSyncedAt {
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VDataRow(tag: "上次校时", tagTint: V8.C.ink4, title: TimeFormat.ago(lastSyncedAt), value: "")
            }
            if syncBusy {
                VBusy(text: "正在把手机时间写进锁…")
                    .padding(.top, V8.S.gapM)
            } else {
                Button { Task { await syncClock() } } label: {
                    Text("同步到锁内")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(readOnly)
                .opacity(readOnly ? 0.45 : 1)
                .padding(.top, V8.S.gapM)
            }
            if let syncResult {
                Text(syncResult.text)
                    .font(V8.T.footnote)
                    .foregroundStyle(syncResult.ok ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VNavRow(title: "重新读取", detail: "读锁内时间再算一次偏差") {
                Task { await readClock() }
            }
            .padding(.top, V8.S.gapS)
            Text("写入的是手机当前时间，不做偏差补偿 —— 所以先确认手机自己的时间是准的。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("锁钟偏了会怎样 · 三条须知")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                VStack(alignment: .leading, spacing: V8.S.gapS) {
                    Text("· 临时码有「有效期窗口」，锁钟偏了，码在窗口外就整段打不开。")
                    Text("· 开锁命令自带有效期，锁钟偏得太多会被判「命令已过期」—— 这种情况只有校时能救。")
                    Text("· 每次读状态时本机都会算一次偏差，超过 2 秒才写；所以这一段平时只是看一眼。")
                }
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            }
            if readOnly {
                Text("只读试验模式已开启：校时下发会被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var clockStatement: String {
        if app.lock == nil { return "还没有门锁可以校" }
        guard let drift = clockDrift else { return "还没读到锁钟" }
        return abs(drift) <= Self.driftThreshold ? "锁钟与手机一致" : "锁钟偏了 " + String(drift) + " 秒"
    }

    private var clockDriftTint: Color {
        guard let drift = clockDrift else { return V8.C.ink3 }
        return abs(drift) <= Self.driftThreshold ? V8.C.ink1 : V8.C.warn
    }

    private var clockDriftNote: String {
        guard let drift = clockDrift else {
            return "还没读到锁钟。走近门锁、确认蓝牙开着，再点下面的「重新读取」。"
        }
        if abs(drift) <= Self.driftThreshold {
            return "偏差在 " + String(Self.driftThreshold) + " 秒以内，不用写。临时码与时间窗凭证此刻是有效的。"
        }
        return "偏差已经超过 " + String(Self.driftThreshold) + " 秒。锁内时间偏了，临时码与时间窗凭证会整段失效 —— 现在同步一次。"
    }

    // MARK: - 段 4 安全模式（← safeMode）

    private var isSafeB: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) != 0 }
    private var isSafeC: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) == 0 }

    private var safeModeSection: some View {
        VCard2 {
            VCardHead(eyebrow: "安全模式", statement: safeModeText)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("A 模式（单验） · 日常最快")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                Text("只需要一种方式验证通过就能开锁：密码、指纹或手机钥匙任一。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("B 模式（双验） · 更安全，多一步")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                Text("需要两种不同方式组合验证：指纹+密码 / 指纹+手机 / 手机+密码。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
                Text("注意：只有 A 模式下动态密码才有效。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, V8.S.gapM)
            if status == nil {
                Text("还没读到锁端模式。走近门锁后点「重新读取锁状态」。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isSafeC {
                Text("当前是 C 模式（广播+验证）。本页只在 A / B 两档之间切换。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isSafeB {
                VNavRow(title: "改回 A 模式（单验，更宽松）", detail: "会降低安全等级，需二次确认") {
                    confirmRelax = true
                }
                .padding(.top, V8.S.gapM)
            } else {
                Button { Task { await setSafeMode(true) } } label: {
                    Text(safeBusy ? "切换中…" : "切换到 B 模式（双验，更严）")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(safeBusy || readOnly)
                .opacity((safeBusy || readOnly) ? 0.45 : 1)
                .padding(.top, V8.S.gapM)
            }
            if let safeOutcome {
                Text(safeOutcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(safeOutcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 段 5 防尾随（← tailgate）

    private var tailgateSection: some View {
        VCard2 {
            VCardHead(eyebrow: "防尾随", statement: tailgateStatement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("门锁用蓝牙钥匙、密码、指纹等电控方式开锁后，等待这段时间会自动上锁。档位 2–6 秒，默认 6 秒。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(2 ... 6, id: \.self) { value in
                        tailgateChip(value)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VDataRow(tag: "当前档位", tagTint: V8.C.ink4, title: String(tailgateSeconds), value: "秒")
            Button {
                Task { await saveTailgate() }
            } label: {
                Text(tailgateBusy ? "正在下发…" : "设置")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(tailgateBusy || !canTailgate || readOnly)
            .opacity((canTailgate && !readOnly) ? 1 : 0.45)
            .padding(.top, V8.S.gapM)
            if let tailgateOutcome {
                Text(tailgateOutcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(tailgateOutcome.hasPrefix("设置成功") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !canTailgate {
                Text("这把锁的型号或固件不支持防尾随（V1 Pro 需固件 1.0.3 以上）。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if readOnly {
                Text("只读试验模式已开启：下发会被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("为什么不是越长越好 · 等待时间就是尾随者能挤进门的那几秒")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                Text("家里有老人小孩可以取 5–6 秒；独居或楼道常有陌生人时取 2–3 秒更稳。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tailgateStatement: String {
        if !canTailgate { return "这把锁不支持防尾随" }
        return "开锁后 " + String(tailgateSeconds) + " 秒自动上锁"
    }

    private func tailgateChip(_ value: Int) -> some View {
        let selected = tailgateSeconds == value
        return Button {
            tailgateSeconds = value
        } label: {
            Text(String(value) + " 秒")
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(value) + " 秒")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 段 6 布防（← defend）

    private var savedDefendMode: DefendModeVM {
        DefendModeVM(rawValue: defendConfig?.control ?? 0) ?? .off
    }

    private var isDefendActiveNow: Bool {
        guard let config = defendConfig else { return false }
        switch savedDefendMode {
        case .off: return false
        case .once: return true
        case .period: return defendInWindow(config.startMinute, config.endMinute, defendNowMinute())
        }
    }

    private var defendSection: some View {
        VCard2 {
            VCardHead(eyebrow: "布防", statement: savedDefendMode.title, trailing: isDefendActiveNow ? "布防中" : "未布防")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if savedDefendMode == .off {
                VDataRow(tag: "此刻", tagTint: V8.C.ink4, title: "自动开锁照常", value: "")
                    .padding(.top, V8.S.gapS)
            } else {
                VStack(spacing: 0) {
                    VDataRow(tag: "此刻", tagTint: isDefendActiveNow ? V8.C.warn : V8.C.ink4, title: isDefendActiveNow ? "布防内" : "布防外", value: "")
                    VDotRule()
                    VDataRow(tag: "时段", tagTint: V8.C.ink4, title: savedDefendMode == .period ? defendPeriodChipText : "全天", value: "")
                    VDotRule()
                    VDataRow(tag: "改动", tagTint: V8.C.ink4, title: "上次改动", value: defendConfig?.updatedAt.map { TimeDisplay.clock($0) } ?? "—")
                }
                .padding(.top, V8.S.gapS)
            }
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(DefendModeVM.allCases.enumerated()), id: \.element.id) { index, m in
                    if index > 0 { VDivider2() }
                    defendModeRow(m)
                }
            }
            if defendMode == .period {
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                defendStepRow(title: "开始", minutes: $startMinute)
                VDivider2()
                defendStepRow(title: "结束", minutes: $endMinute)
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                Text(defendPeriodNote)
                    .font(V8.T.footnote)
                    .foregroundStyle(defendPeriodValid ? V8.C.ink3 : V8.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            if defendBusy {
                VBusy(text: defendMode == .off ? "正在撤防…" : "正在布防…")
            } else {
                Button {
                    askDefendConfirm = true
                } label: {
                    Text(defendActionTitle)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(!defendCanApply || readOnly)
                .opacity((defendCanApply && !readOnly) ? 1 : 0.45)
            }
            if !defendCanApply {
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
            if let defendOutcome {
                if defendOutcomeOK {
                    Text(defendOutcome)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ok)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VFailure(
                        what: "布防没有下发成功",
                        why: defendOutcome,
                        next: "确认手机在门锁旁边、蓝牙已开；命令只回「收到」不代表已生效，回读后再判断。"
                    ) {
                        askDefendConfirm = true
                    }
                    .padding(.top, V8.S.gapS)
                }
            }
            Text("锁只回了「收到命令」，并没有回报当前的布防状态 —— 所以这里不会说「已进入布防」，只记录本机状态与这次回执。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("布防期间会发生什么 · 否决自动开锁，不否决手动开锁")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
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
    }

    private var defendPeriodChipText: String {
        guard savedDefendMode == .period else { return "全天" }
        let start = defendClockLabel(defendConfig?.startMinute ?? startMinute)
        let end = defendClockLabel(defendConfig?.endMinute ?? endMinute)
        return start + "–" + end
    }

    private func defendModeRow(_ m: DefendModeVM) -> some View {
        let on = defendMode == m
        return Button {
            defendMode = m
            defendOutcome = nil
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

    private func defendStepRow(title: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: V8.S.gapM) {
            Text(title)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
            Spacer(minLength: V8.S.gapS)
            Text(defendClockLabel(minutes.wrappedValue))
                .font(V8.T.value)
                .foregroundStyle(V8.C.ink1)
                .monospacedDigit()
            defendStepButton("minus", label: title + "提前 15 分钟") {
                minutes.wrappedValue = defendWrapMinutes(minutes.wrappedValue - Self.minuteStep)
            }
            defendStepButton("plus", label: title + "推迟 15 分钟") {
                minutes.wrappedValue = defendWrapMinutes(minutes.wrappedValue + Self.minuteStep)
            }
        }
        .frame(minHeight: V8.H.min)
    }

    private func defendStepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
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

    private var defendPeriodValid: Bool {
        startMinute != endMinute
    }

    private var defendPeriodNote: String {
        if !defendPeriodValid {
            return "开始与结束相同 —— 锁端会把它当成全天布防。要设成某个时段，请把结束时间挪开一档。"
        }
        if endMinute < startMinute {
            return "跨午夜时段：" + defendClockLabel(startMinute) + " 到次日 " + defendClockLabel(endMinute) + "。这段时间里靠近门锁不会自动开门。"
        }
        return "时段内进入布防，时段外正常开锁。跨午夜指开始晚于结束。"
    }

    private var defendCanApply: Bool {
        defendMode == .period ? defendPeriodValid : true
    }

    private var defendActionTitle: String {
        switch defendMode {
        case .off: return "执行撤防"
        case .once: return "执行布防"
        case .period: return "保存时段并布防"
        }
    }

    private var defendConfirmMessage: String {
        switch defendMode {
        case .off:
            return "撤防后门锁恢复正常开锁，靠近自动开锁也会恢复。随时可以重新布防 —— 可以撤销。"
        case .once:
            return "门锁进入不定期布防，直到你手动撤防。布防期间靠近门锁不会自动开门；在本页撤防即可恢复。"
        case .period:
            return "时段 " + defendClockLabel(startMinute) + " – " + defendClockLabel(endMinute) + " 内布防；时段内自动开锁会被一票否决。随时可以在本页撤防恢复自动开锁。"
        }
    }

    // MARK: - 卡 7 危险操作

    private var dangerCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "危险操作", statement: "清空后不能撤销")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("清空全部密码会把锁里所有密码作废（指纹保留），并同时清空本机密码台账。清空后需要重新逐条添加。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text("键入「清空」确认")
                    .font(V8.T.label)
                    .foregroundStyle(V8.C.ink4)
                TextField("清空", text: $clearTyped)
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink1)
                    .frame(minHeight: V8.H.min)
                    .padding(.horizontal, V8.S.gapM)
                    .background(V8.C.card, in: .rect(cornerRadius: V8.R.inset))
            }
            .padding(.top, V8.S.gapM)
            Button {
                clearConfirm = true
            } label: {
                Text("清空全部密码")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .disabled(clearTyped != "清空" || busy || !canClearPwd || app.trialGuard)
            .opacity(clearTyped == "清空" && canClearPwd && !busy && !app.trialGuard ? 1 : 0.45)
            .padding(.top, V8.S.gapM)
            if !canClearPwd {
                Text("这把锁的型号不支持清空密码。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("先键入「清空」两个字，按钮才可用；点下去还会再问一次。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 行构件

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Text(detail)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V8.H.min)
        .padding(.top, V8.S.gapS)
    }

    // MARK: - 读数

    private var firmwareText: String {
        if let f = status?.firmware, !f.isEmpty { return f }
        if let f = kc?.fw, !f.isEmpty { return f }
        return "未知"
    }

    private var bootText: String {
        let v = status?.verDFU ?? 0
        return v > 0 ? String(v) : "该固件未上报"
    }

    private var keyboardText: String {
        let v = status?.verKeyboard ?? 0
        return v > 0 ? String(v) : "该固件未上报"
    }

    private var pwdCapacityText: String {
        let snap = DB.readStatus(mac)
        return capacityText(used: (snap?.pwdCap ?? 0) - (snap?.pwdStock ?? 0), cap: snap?.pwdCap ?? 0)
    }

    private var fpCapacityText: String {
        let snap = DB.readStatus(mac)
        return capacityText(used: (snap?.fpCap ?? 0) - (snap?.fpStock ?? 0), cap: snap?.fpCap ?? 0)
    }

    /// 容量读数两个数都要读成「已用 / 容量」；容量未读时只报已用，并说清容量确实没读到。
    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? String(max(used, 0)) + " / " + String(cap) : "已用 " + String(max(used, 0)) + " · 容量未读"
    }

    private var canTailgate: Bool {
        guard let kc else { return false }
        return PidMap.canTailgate(kc.pid, fw: kc.fw)
    }

    private var canClearPwd: Bool {
        guard let kc else { return false }
        return PidMap.canClearPwd(kc.pid)
    }

    private var safeModeText: String {
        guard let st = status else { return "未读到" }
        if st.verifyMode == 1 && st.broadcastMode != 0 { return "B · 双验" }
        if st.verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    // MARK: - 读

    private func load(force: Bool = false) async {
        guard !decoyed, !mac.isEmpty, !busy else { return }
        otpOn = DB.otpStatus(mac)?.on ?? false
        muted = DB.store.getBool("kf_muted_" + mac)
        if !tailgateLoaded {
            autoLock = DB.tailgate(mac)?.interval ?? 6
            tailgateSeconds = autoLock
            tailgateLoaded = true
        }
        if !defendLoaded {
            loadDefend()
            defendLoaded = true
        }
        guard force || status == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            status = st
            DB.writeStatus(mac, st)
            muted = st.soundVolumn > 0 || muted
            outcome = "已读取锁实况"
            outcomeIsFailure = false
            readError = nil
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            readError = msg
            outcome = msg
            outcomeIsFailure = true
        }
    }

    /// 「这台锁」段的重读入口（← lockStatus 的 reread）：读一次锁状态，刷新全部读数。
    private func reread() {
        guard !busy else { return }
        busy = true
        Task {
            await load(force: true)
            await readClock()
            busy = false
        }
    }

    // MARK: - 锁钟真链路（← syncTime）

    @MainActor
    private func readClock() async {
        guard app.lock != nil, !syncBusy else { return }
        syncBusy = true
        defer { syncBusy = false }
        await app.refreshStatus()
        if let t = app.lastStatus?.status.lockTime, t > 0 {
            lockAt = Int64((ZKProtocol.protoSecondsToUnix(Int64(t)) * 1000).rounded())
        } else {
            lockAt = nil
        }
        syncResult = nil
    }

    @MainActor
    private func syncClock() async {
        guard !syncBusy, app.lock != nil, !readOnly, !decoyed else { return }
        let mac = app.currentMac
        syncBusy = true
        syncResult = nil
        let r = await app.syncTime()
        syncBusy = false
        switch r {
        case .failure(let e):
            let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            syncResult = SyncOutcome(ok: false, text: "同步失败：" + msg)
        case .success(let pair):
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let drift = pair.1
            lockAt = now + Int64(drift) * 1000
            lastSyncedAt = now
            DB.saveSyncTime(mac, Double(now))
            let residual = -drift
            syncResult = SyncOutcome(ok: abs(residual) <= Self.driftThreshold,
                                     text: "同步完成 · 回读偏差 " + String(residual) + " 秒")
        }
    }

    // MARK: - 安全模式真链路（← safeMode）

    private func setSafeMode(_ double: Bool) async {
        let mac = self.mac
        guard !mac.isEmpty, !safeBusy, !readOnly, !decoyed else { return }
        safeBusy = true
        safeOutcome = nil
        defer { safeBusy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setValidationMode(double)
            let st = try await LockService.shared.getStatus(mac: mac)
            status = st
            DB.writeStatus(mac, st)
            await app.refreshStatus()
            let ok = double ? (st.verifyMode == 1 && st.broadcastMode != 0) : (st.verifyMode == 0)
            safeOutcome = ok
                ? (double ? "已切到 B 模式（双验），回读确认" : "已切回 A 模式（单验），回读确认")
                : "命令已下发，但回读显示未生效 —— 请重读后再试"
        } catch {
            safeOutcome = "切换失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 防尾随真链路（← tailgate）

    private func saveTailgate() async {
        let mac = self.mac
        guard !mac.isEmpty, !tailgateBusy, !readOnly, !decoyed else { return }
        tailgateBusy = true
        tailgateOutcome = nil
        defer { tailgateBusy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setAutoLock(tailgateSeconds)
            DB.saveTailgate(mac, TailgateCfg(interval: tailgateSeconds, at: Date().timeIntervalSince1970 * 1000))
            autoLock = tailgateSeconds
            tailgateOutcome = "设置成功：开锁后 " + String(tailgateSeconds) + " 秒自动上锁"
        } catch {
            tailgateOutcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 布防真链路（← defend）

    private func loadDefend() {
        guard !decoyed else { return }
        guard let kc = app.currentKeychain else { return }
        if let c = DB.defend(kc.mac) {
            defendConfig = DefendConfigVM(control: c.control,
                                          startMinute: DefendKit.secFromProto(c.startSec) / 60,
                                          endMinute: DefendKit.secFromProto(c.endSec) / 60,
                                          updatedAt: Int64(c.at))
            defendMode = DefendModeVM(rawValue: c.control) ?? .off
            startMinute = defendConfig?.startMinute ?? startMinute
            endMinute = defendConfig?.endMinute ?? endMinute
        } else {
            defendConfig = DefendConfigVM(control: 0, startMinute: 22 * 60, endMinute: 7 * 60, updatedAt: nil)
            defendMode = .off
        }
    }

    @MainActor
    private func applyDefend() async {
        guard !defendBusy, defendCanApply, !decoyed, !readOnly, let kc = app.currentKeychain else { return }
        defendBusy = true
        defendOutcome = nil
        defendOutcomeOK = true
        let dm = DefendMode(rawValue: defendMode.rawValue) ?? .off
        let startSec = defendMode == .period ? startMinute * 60 : 0
        let endSec = defendMode == .period ? endMinute * 60 : 0
        do {
            // 真链路：下发布防 → 成功才写本地 kf_defend_。
            try await DefendService.apply(host: app, mode: dm, startSec: startSec, endSec: endSec)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            defendConfig = DefendConfigVM(control: defendMode.rawValue,
                                          startMinute: startMinute,
                                          endMinute: endMinute,
                                          updatedAt: now)
            defendOutcome = defendMode == .off ? "已撤防（锁端回执成功）" : "已布防（锁端回执成功）"
            defendOutcomeOK = true
            _ = kc
        } catch {
            defendOutcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            defendOutcomeOK = false
        }
        defendBusy = false
    }

    // MARK: - 布防工具

    private func defendClockLabel(_ minutes: Int) -> String {
        let m = defendWrapMinutes(minutes)
        let hh = m / 60
        let mm = m % 60
        return DF.pad2(hh) + ":" + DF.pad2(mm)
    }

    private func defendWrapMinutes(_ minutes: Int) -> Int {
        let span = 24 * 60
        let v = minutes % span
        return v < 0 ? v + span : v
    }

    private func defendNowMinute(_ date: Date = Date()) -> Int {
        let comps = TimeFormat.calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// 时段判定：start == end 按全天布防（fail-closed，不退化成空集）；跨午夜取两段。
    private func defendInWindow(_ start: Int, _ end: Int, _ now: Int) -> Bool {
        if start == end { return true }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }

    // MARK: - 写（本体能力，保持不变）

    private func writeOtp(_ on: Bool) {
        // E-07：进函数先把 MAC 固定成局部常量。mac 是计算属性（app.lock?.id），
        // await 期间用户换锁会让结果写到新锁的 kf_otp_ 键上。
        let mac = self.mac
        guard !mac.isEmpty, !busy else { return }
        guard !DB.isDecoy else {
            actionError = "空壳模式下不写入设置 —— 先退出空壳再来改。"
            return
        }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        actionError = nil
        Task {
            defer { busy = false }
            do {
                try await LockService.shared.ensureConnected(mac: mac)
                try await LockService.shared.setZotp(on)
                DB.saveOtpStatus(mac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                otpOn = on
                actionError = nil
                outcome = on ? "动态密码已开通" : "动态密码已关闭"
                outcomeIsFailure = false
                AppToast.shared.show(outcome ?? "", tone: .ok)
            } catch {
                otpOn = !on
                outcome = nil
                outcomeIsFailure = true
                actionError = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func writeMuted(_ on: Bool) {
        // E-07：同上 —— 静音位写到错误的锁是「用户以为给 A 静音，实际是 B 静音」。
        let mac = self.mac
        guard !mac.isEmpty, !busy, !readOnly else { return }
        guard !DB.isDecoy else {
            actionError = "空壳模式下不写入设置 —— 先退出空壳再来改。"
            return
        }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        actionError = nil
        Task {
            defer { busy = false }
            do {
                // 走 AppModel.setMuted 这条唯一路径：它会顺带 refreshStatus 刷新门页投影。
                let r = await app.setMuted(on)
                if case .failure(let e) = r { throw e }
                muted = on
                policyRev += 1
                actionError = nil
                outcome = on ? "已静音：键盘与开锁不提示音" : "已恢复提示音"
                outcomeIsFailure = false
            } catch {
                muted = !on
                policyRev += 1
                outcome = nil
                outcomeIsFailure = true
                actionError = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 安全模式写入（← lockStatus 的 writeSafeMode）：只许变严；放宽走 confirmRelax。
    private func writeSafeMode(_ on: Bool) {
        guard app.lock != nil, !busy, !readOnly else { return }
        guard !DB.isDecoy else {
            outcomeIsFailure = true
            outcome = "空壳模式下不写入锁端策略 —— 先退出空壳再来改。"
            return
        }
        busy = true
        Task {
            let r = await app.setSafeMode(on)
            busy = false
            policyRev += 1
            if case .failure(let e) = r {
                outcomeIsFailure = true
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcomeIsFailure = false
                outcome = on ? "已切到双验（A/B 模式）" : "已切回单验"
            }
            await load(force: true)
        }
    }

    private func runClearPwd() async {
        let mac = self.mac   // E-07：await 期间换锁不能把清空动作落到另一把锁的台账
        guard !mac.isEmpty, !busy else { return }
        guard !DB.isDecoy else {
            actionError = "空壳模式下不清空任何密码 —— 先退出空壳再操作。"
            return
        }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        actionError = nil
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdClear()
            var l = DB.ledger(mac)
            l.pwds = []
            DB.saveLedger(mac, l)
            app.reloadKeys(mac)
            clearTyped = ""
            actionError = nil
            outcome = "已清空全部密码（指纹保留）"
            outcomeIsFailure = false
            AppToast.shared.show("已清空全部密码", tone: .ok)
        } catch {
            outcome = nil
            outcomeIsFailure = true
            actionError = "清空失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
