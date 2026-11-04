// LockSettingsHomeScreen.swift —— 锁设置（V8 设计语言）
//
// 与 LockSettingsScreen 的能力对齐：动态密码开通/关闭、静音、防尾随读数与入口、
// 安全模式读数与说明、电池档案 / 锁档案 / 全部锁三个入口、这台锁的只读读数（含重新读取）、
// 清空全部密码（键入「清空」+ 二次确认）。
// 只改渲染层：写动作仍走 LockService.ensureConnected → setZotp / app.setMuted / pwdClear，
// 落盘仍是 otpStatus_<mac> / kf_muted_<mac> / 台账（失败一律不改本机镜像）。
//
// 与旧页的两处刻意差异：
//   ① 空壳模式（胁迫码进入）下整页只显示一张说明卡：旧页会把真实锁名与锁端读数摊在屏幕上，
//      且「清空全部密码」在空壳里也点得动 —— 与「空壳只隐藏、不破坏」相反。
//   ② 危险动作收口到统一的 .v8Confirm，并把「不可撤销」写进后果句。
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
    @State private var showSafeMode = false
    @State private var tailgateLoaded = false

    private var mac: String { app.lock?.id ?? "" }
    private var decoyed: Bool { DB.isDecoy }
    private var kc: Keychain? { app.currentKeychain }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不显示锁设置" }
        guard let lock = app.lock else { return "还没有门锁可设置" }
        return lock.name + " · " + (otpOn ? "动态码已开通" : "动态码已关闭")
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏、不改动：本页既不显示这把锁的策略，也不写入任何设置。退出空壳后才能改。" }
        if app.lock == nil { return "锁设置改的是具体一把锁的锁端策略：先添加并配对门锁，再回这一页。" }
        return "这一页改的都是锁端策略：写成功后回读确认，本机只留一份镜像。只读读数在最后一张卡。"
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
                VEmpty(
                    title: "还没有门锁可设置",
                    reason: "锁设置改的是具体一把锁的锁端策略：先添加并配对门锁，再回这一页。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                if app.trialGuard { trialCard }
                if let actionError { actionErrorCard(actionError) }
                tempCodeCard
                policyCard
                entriesCard
                overviewCard
                dangerCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showSafeMode) { NavigationStack { SafeModeHomeScreen() } }
        .v8Confirm(
            isPresented: $clearConfirm,
            title: "清空全部密码？",
            consequence: "会把锁里所有密码作废（指纹保留），本机密码台账同时清空。这一步不可撤销：清空后只能逐条重新添加。",
            confirmTitle: "清空密码",
            isDestructive: true
        ) {
            Task { await runClearPwd() }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph("clock.badge.questionmark"), label: "动态密码", value: otpOn ? "已开通" : "已关闭")
                VChip2(icon: .glyph("speaker.wave.2.fill"), label: "提示音", value: muted ? "静音" : "正常")
                VChip2(icon: .glyph("figure.walk.arrival"), label: "防尾随", value: canTailgate ? "\(autoLock) 秒" : "不支持")
                VChip2(icon: .glyph("lock.rotation"), label: "安全模式", value: safeModeText)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
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
            Text("这一页的动态密码、静音与清空密码都要下发到门锁，护栏会把它们拦下。本机读数照常可读。要改设置，先到「安全」页关掉只读试验模式。")
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
                detail: otpOn ? "已开通 · 锁端会接受动态码" : "已关闭 · 动态码不会被锁接受",
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

    // MARK: - 卡 2 锁端策略

    private var policyCard: some View {
        VCard2 {
            VCardHead(eyebrow: "锁端策略", statement: muted ? "静音 · 键盘与开锁不提示音" : "提示音正常")
            VDivider2()
                .padding(.top, V8.S.gapM)
            toggleRow(
                "静音",
                detail: muted ? "开 · 键盘与开锁不提示音" : "关 · 正常提示音",
                isOn: Binding(
                    get: { muted },
                    set: { on in writeMuted(on) }
                )
            )
            .disabled(app.trialGuard)
            .opacity(app.trialGuard ? 0.45 : 1)
            VDotRule()
                .padding(.top, V8.S.gapS)
            VDataRow(tag: "防尾随", tagTint: V8.C.ink4, title: "自动上锁", value: "\(autoLock)", unit: "秒")
            Text("电控开锁后等待几秒自动上锁；2–6 秒可调。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "设置防尾随等待时长", detail: canTailgate ? "2–6 秒，下发后回读" : "这把锁的型号或固件不支持") {
                router.request(.dest(.tailgate))
            }
            .disabled(!canTailgate)
            .opacity(canTailgate ? 1 : 0.45)
            VDotRule()
                .padding(.top, V8.S.gapS)
            VDataRow(tag: "安全模式", tagTint: V8.C.ink4, title: safeModeText, value: "")
            Text("A 模式单验、B 模式双验；切换要连上锁并回读确认。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "打开安全模式说明", detail: "A / B / C 三档的差别") {
                showSafeMode = true
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 3 更多入口

    private var entriesCard: some View {
        VCard2 {
            VCardHead(eyebrow: "更多", statement: "这三个入口只在锁设置里")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VNavRow(title: "电池档案", detail: "电量采样 / 五档 / 电池型号与换电日期") {
                router.request(.dest(.batteryProfile))
            }
            .padding(.top, V8.S.gapS)
            VDotRule()
            VNavRow(title: "锁档案", detail: "昵称 / 符号 / 色标 / 分组 / 解锁 PIN") {
                router.request(.dest(.lockProfile))
            }
            VDotRule()
            VNavRow(title: "全部锁", detail: "多锁统计 / 分组 / 排序") {
                router.request(.dest(.lockPortfolio))
            }
        }
    }

    // MARK: - 卡 4 这台锁 · 只读

    private var overviewCard: some View {
        VCard2 {
            VCardHead(eyebrow: "这台锁 · 只读", statement: firmwareText)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: PidMap.productName(kc?.pid ?? 0), value: "")
                VDotRule()
                VDataRow(tag: "固件", tagTint: V8.C.ink4, title: firmwareText, value: "")
                VDotRule()
                VDataRow(tag: "Boot", tagTint: V8.C.ink4, title: bootText, value: "")
                VDotRule()
                VDataRow(tag: "键盘", tagTint: V8.C.ink4, title: keyboardText, value: "")
                VDotRule()
                VDataRow(tag: "密码容量", tagTint: V8.C.ink4, title: pwdCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "指纹容量", tagTint: V8.C.ink4, title: fpCapacityText, value: "")
                VDotRule()
                VDataRow(tag: "锁钟偏差", tagTint: driftTint, title: driftText, value: "")
                VDotRule()
                VDataRow(tag: "电量", tagTint: batteryTint, title: batteryText, value: "")
            }
            .padding(.top, V8.S.gapS)
            if busy {
                VBusy(text: "正在与门锁通信…")
                    .padding(.top, V8.S.gapM)
            } else if let readError {
                VFailure(
                    what: "读取锁状态失败",
                    why: readError,
                    next: "走近门锁、确认蓝牙开着，再点下面的「重新读取锁状态」。",
                    retry: { Task { await load(force: true) } }
                )
                .padding(.top, V8.S.gapM)
            } else if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcomeIsFailure ? V8.C.danger : V8.C.ok)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VDivider2()
                .padding(.top, V8.S.gapM)
            VNavRow(title: "重新读取锁状态", detail: "读一次锁端快照并回写本机") {
                Task { await load(force: true) }
            }
            VNavRow(title: "查看完整锁信息名片", detail: "含固件服役 / 绑定时间 / 电量采样") {
                router.request(.dest(.deviceInfo))
            }
        }
    }

    // MARK: - 卡 5 危险操作

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
        return v > 0 ? "\(v)" : "该固件未上报"
    }

    private var keyboardText: String {
        let v = status?.verKeyboard ?? 0
        return v > 0 ? "\(v)" : "该固件未上报"
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
        cap > 0 ? "\(max(used, 0)) / \(cap)" : "已用 \(max(used, 0)) · 容量未读"
    }

    private var driftText: String {
        // 0 = 锁端没回时钟 —— 不能拿它算偏差（会得到 ≈ -531260264 秒）。
        guard let t = status?.lockTime, t > 0 else { return "未读到锁钟" }
        let dev = Int(t - ZKProtocol.nowProtoSeconds())
        if dev == 0 { return "与手机一致" }
        return (dev > 0 ? "+" : "") + "\(dev) 秒"
    }

    private var driftTint: Color {
        guard let t = status?.lockTime, t > 0 else { return V8.C.ink4 }
        let dev = Int(t - ZKProtocol.nowProtoSeconds())
        return abs(dev) > 60 ? V8.C.warn : V8.C.ink4
    }

    private var batteryText: String {
        let p = BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1)
        return BatteryCare.faceText(p)
    }

    private var batteryTint: Color {
        let p = BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1)
        return p >= 0 && p <= 20 ? V8.C.warn : V8.C.ink4
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
            tailgateLoaded = true
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

    // MARK: - 写

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
                // 走 AppModel.setMuted 这条唯一路径：它会顺带 refreshStatus 刷新门页投影。
                let r = await app.setMuted(on)
                if case .failure(let e) = r { throw e }
                muted = on
                actionError = nil
                outcome = on ? "已静音：键盘与开锁不提示音" : "已恢复提示音"
                outcomeIsFailure = false
            } catch {
                muted = !on
                outcome = nil
                outcomeIsFailure = true
                actionError = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
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
