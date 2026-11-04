// LockStatusHomeScreen.swift —— 锁实况（V8 设计语言）
//
// 与 LockStatusScreen 的能力对齐：电量 / 信号 / 本机凭证 / 固件 / 型号 / 链路读数，
// 安全模式（只许变严，放宽要二次确认）与静音两枚即点即写的锁端开关，四个下钻入口。
// 只改渲染层：写入仍走 app.setSafeMode / app.setMuted / app.refreshStatus。
//
// 与旧页的两处刻意差异：
//   ① 空壳模式（胁迫码）下不显示锁名与任何读数 —— 通用钥匙串读取返回的是真锁，
//      锁名与档案都是真值，不能摊给被胁迫者看。
//   ② 只读试验模式明确显示并禁用两枚开关，不再让用户点了才发现命令被拦。
import SwiftUI

struct LockStatusHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var writing = false
    @State private var outcome: String?
    /// 结果行是否成功。不从文案里猜（「锁忙」这类失败文案一个失败字都没有）。
    @State private var outcomeOK = true
    /// 每次写入（成功或失败）都 +1：PolicyToggle 靠它重新对齐 isOn。
    @State private var policyRev = 0
    @State private var confirmRelax = false
    @State private var readError: String?

    private var lock: LockSummary? { app.lock }
    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式不显示锁实况" }
        guard let lock else { return "还没有门锁可以读" }
        return lock.isConnected ? lock.name + " · 链路已建立" : lock.name + " · 链路未建立"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。锁照样能开，但读数与锁端策略不在这里显示。"
        }
        guard let lock else {
            return "读数要靠蓝牙直连才拿得到：先把锁加进来，再回这一页看电量与固件。"
        }
        if lock.isConnected {
            return "读数来自上一次直连回读；两枚开关即点即写，回执成功才更新。"
        }
        return lock.name + " 此刻不在线。走近门锁、确认蓝牙开着，再点「重读」。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if !decoyed && lock != nil {
                chipRow
            } else {
                EmptyView()
            }
        } content: {
            if decoyed {
                decoyCard
            } else if let lock {
                readingsCard(lock)
                if let readError {
                    VFailure(
                        what: "锁实况没读回来",
                        why: readError,
                        next: "走近门锁、确认手机蓝牙已开，再点重试。"
                    ) {
                        reread()
                    }
                }
                policyCard(lock)
                entriesCard
            } else {
                VEmpty(
                    title: "还没有门锁可以读",
                    reason: "读数要靠蓝牙直连才拿得到：先把锁加进来（打开后面板，长按 RESET 到三声嘀），再回这一页看电量与固件。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .v8Confirm(
            isPresented: $confirmRelax,
            title: "放宽安全模式？",
            consequence: "放宽后一枚凭证就能单独开门，这是降低安全等级。之后可以随时切回双验，但放宽期间发生的开门无法撤回。",
            confirmTitle: "放宽",
            isDestructive: true
        ) {
            writeSafeMode(false)
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(batteryFraction, batteryTint), label: "电量", value: batteryChipText)
                VChip2(icon: .ring(signalFraction, signalTint), label: "信号", value: signalChipText)
                VChip2(icon: .glyph("shield.lefthalf.filled"), label: "安全模式", value: safeChipText)
                VChip2(icon: .glyph("bell.slash.fill"), label: "静音", value: muteChipText)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var batteryFraction: Double {
        guard let lock, lock.battery >= 0 else { return 0.02 }
        return min(1, max(0.02, Double(lock.battery) / 100))
    }

    private var batteryTint: Color {
        guard let lock, lock.battery >= 0 else { return V8.C.ink4 }
        return lock.battery <= 20 ? V8.C.warn : V8.C.ok
    }

    private var batteryChipText: String {
        guard let lock, lock.battery >= 0 else { return "未知" }
        return String(lock.battery) + "%"
    }

    private var signalFraction: Double {
        guard let lock, lock.signal > 0 else { return 0.02 }
        return min(1, max(0.02, Double(lock.signal) / 4))
    }

    private var signalTint: Color {
        guard let lock, lock.signal > 0 else { return V8.C.ink4 }
        return lock.signal == 1 ? V8.C.warn : V8.C.ok
    }

    private var signalChipText: String {
        guard let lock, lock.signal > 0 else { return "未测" }
        return String(lock.signal) + "/4"
    }

    private var safeChipText: String {
        guard let lock else { return "未读" }
        return lock.safeMode ? "双验" : "单验"
    }

    private var muteChipText: String {
        guard let lock else { return "未读" }
        return lock.muted ? "无声" : "有声"
    }

    // MARK: - 卡 1 运行状态

    private func readingsCard(_ lock: LockSummary) -> some View {
        VCard2 {
            VCardHead(eyebrow: "运行状态", statement: readingStatement(lock), trailing: "锁端读数")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "电量", tagTint: batteryTint, title: "当前电量", value: batteryValue(lock), unit: batteryUnit(lock))
                VDotRule()
                VDataRow(tag: "信号", tagTint: signalTint, title: "链路信号", value: signalValue(lock), unit: signalUnit(lock))
                VDotRule()
                VDataRow(tag: "凭证", tagTint: V8.C.ink4, title: "本机凭证", value: String(lock.keyCount), unit: "枚")
                VDotRule()
                VDataRow(tag: "固件", tagTint: V8.C.ink4, title: "锁内固件", value: lock.firmware.isEmpty ? "未读到" : lock.firmware)
                VDotRule()
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: "产品型号", value: lock.model)
                VDotRule()
                VDataRow(tag: "链路", tagTint: V8.C.ink4, title: "连接方式", value: lock.isConnected ? "蓝牙直连" : "未建立")
                VDotRule()
                VDataRow(tag: "开锁", tagTint: V8.C.ink4, title: "上次开锁", value: lastOpenText)
            }
            .padding(.top, V8.S.gapS)
            Text("信号 0 表示还没测过，不代表信号差；电量未读到时不显示数字。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readingStatement(_ lock: LockSummary) -> String {
        if lock.battery < 0 { return "还没读到电量" }
        return "这一把锁的读数"
    }

    private func batteryValue(_ lock: LockSummary) -> String {
        lock.battery < 0 ? "未知" : String(lock.battery)
    }

    private func batteryUnit(_ lock: LockSummary) -> String? {
        lock.battery < 0 ? nil : "%"
    }

    private func signalValue(_ lock: LockSummary) -> String {
        lock.signal <= 0 ? "未测" : String(lock.signal)
    }

    private func signalUnit(_ lock: LockSummary) -> String? {
        lock.signal <= 0 ? nil : "/ 4"
    }

    private var lastOpenText: String {
        guard let at = app.lastActionAt else { return "还没有开锁记录" }
        return TimeFormat.ago(at)
    }

    // MARK: - 卡 2 锁端策略

    private func policyCard(_ lock: LockSummary) -> some View {
        VCard2 {
            VCardHead(eyebrow: "锁端策略", statement: readOnly ? "只读试验模式 · 不可写" : "即点即写")
            VDivider2()
                .padding(.top, V8.S.gapM)
            switchRow(
                title: "安全模式",
                note: "A / B 模式决定验一次还是两次。只许变严；放宽要二次确认。",
                isOn: lock.safeMode,
                onWord: "开 · 双验",
                offWord: "关 · 单验"
            ) { on in
                if on { writeSafeMode(true) } else { confirmRelax = true }
            }
            .disabled(readOnly)
            .opacity(readOnly ? 0.55 : 1)

            VDivider2()
                .padding(.vertical, V8.S.gapM)

            switchRow(
                title: "静音",
                note: "锁端提示音关掉后，按键只给机械反馈，不发声。",
                isOn: lock.muted,
                onWord: "开 · 无声",
                offWord: "关 · 有声"
            ) { on in
                writeMuted(on)
            }
            .disabled(readOnly)
            .opacity(readOnly ? 0.55 : 1)

            pendingLine
            if readOnly {
                Text("只读试验模式已开启：写入类命令全部停用。到「设置 → 安全 → 只读试验模式」关掉再改。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 带本地状态的政策开关：手指动作立刻反映，锁端写入结果回来后再覆盖。
    /// revision 变化（每次写入成功或失败）时重新按 isOn 校准。
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

    private func switchRow(
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
        }
        .frame(minHeight: V8.H.min)
    }

    private var pendingLine: some View {
        HStack(spacing: V8.S.gapS) {
            if writing {
                VBusy(text: "正在下发…")
            } else if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcomeOK ? V8.C.ok : V8.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("还没改过 · 开关改动会立即下发")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink4)
            }
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

    // MARK: - 卡 3 下钻入口

    private var entriesCard: some View {
        VCard2 {
            VCardHead(eyebrow: "读数不对时", statement: "四个入口")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "锁设置", detail: "动态密码开关 / 自动上锁 / 清空密码") {
                    router.request(.dest(.lockSettings))
                }
                VDivider2()
                VNavRow(title: "校时", detail: "锁钟偏了，临时码与时间窗凭证会失效") {
                    router.request(.dest(.syncTime))
                }
                VDivider2()
                VNavRow(title: "布防", detail: "布防时段内，靠近门锁不会自动开门") {
                    router.request(.dest(.defend))
                }
                VDivider2()
                VNavRow(title: "网关", detail: "只看状态与告警，不能远程开门") {
                    router.request(.dest(.gateway))
                }
            }
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁实况", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，锁名、电量、固件与锁端策略都不显示。读与写都会碰真实数据，这里一并停掉。")
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

    // MARK: - 写入

    /// 安全模式：真链路 app.setSafeMode（1 = 双验）。回包失败才报错。
    private func writeSafeMode(_ on: Bool) {
        guard app.lock != nil, !writing, !readOnly else { return }
        guard !DB.isDecoy else {
            outcomeOK = false
            outcome = "空壳模式下不写入锁端策略 —— 先退出空壳再来改。"
            return
        }
        writing = true
        Task {
            let r = await app.setSafeMode(on)
            writing = false
            policyRev += 1
            if case .failure(let e) = r {
                outcomeOK = false
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcomeOK = true
                outcome = on ? "已切到双验（A/B 模式）" : "已切回单验"
            }
        }
    }

    /// 静音：真链路 app.setMuted（0 = 有声 / 1 = 静音）。
    private func writeMuted(_ on: Bool) {
        guard app.lock != nil, !writing, !readOnly else { return }
        guard !DB.isDecoy else {
            outcomeOK = false
            outcome = "空壳模式下不写入锁端策略 —— 先退出空壳再来改。"
            return
        }
        writing = true
        Task {
            let r = await app.setMuted(on)
            writing = false
            policyRev += 1
            if case .failure(let e) = r {
                outcomeOK = false
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcomeOK = true
                outcome = on ? "已静音：键盘与开锁不提示音" : "已恢复提示音"
            }
        }
    }

    /// 读一次锁状态，刷新这一页的全部读数。
    private func reread() {
        guard !writing else { return }
        writing = true
        readError = nil
        Task {
            await app.refreshStatus()
            writing = false
            if let e = app.lastError {
                readError = e
                app.lastError = nil
            } else {
                readError = nil
                outcomeOK = true
                outcome = "已重新读取锁实况"
            }
        }
    }
}
