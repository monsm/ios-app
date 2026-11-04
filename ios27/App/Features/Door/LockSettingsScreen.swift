// LockSettingsScreen.swift —— 锁设置（门 · 这一把锁的策略页）。
//
// 来源：原 App/UI/LockSettingsView.swift（锁设置 7 项能力）+ SettingsView 的「清空密码」危险区。
// 这屏干什么：把 cmd18 静音、cmd19 临时码开关、cmd20 安全模式、cmd24 自动上锁/防尾随、
//   清空全部密码（0A delAlias=FFFF）与固件/校时/电池/档案入口收在同一页；读数来自 cmd03 快照。
// 数据从哪来：AppModel.lock / DB.readStatus / LockService.getStatus（进页静默读一次）；
//   写入一律 ensureConnected → 成功才回写本机键（失败不假装成功）。
// 主动作：本屏没有强主色按钮 —— 每个开关都是独立写动作；「清空全部密码」单独红色危险区。
import SwiftUI

struct LockSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var otpOn = false
    @State private var muted = false
    @State private var autoLock = 6
    @State private var busy = false
    @State private var outcome: String?
    /// 最近一次读取是成功还是失败 —— 决定 outcome 的语义色。
    @State private var outcomeIsFailure = false
    @State private var clearConfirm = false
    @State private var clearTyped = ""
    @State private var showSafeMode = false
    @State private var tailgateLoaded = false

    private var mac: String { app.lock?.id ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if app.lock == nil {
                    noLockCard
                } else {
                    // 2026-11-03（整页截图实测 · 信息架构）：原来第一张卡是**整屏只读读数**
                    // （型号 / 固件 / Boot / 键盘 / 密码容量 / 指纹容量 / 锁钟偏差 / 电量）——
                    // 与「锁信息名片」页几乎逐行重复，把真正的设置项（临时码 / 静音 / 安全模式）
                    // 整整压到第二屏。用户点「锁设置」是来改设置的，不是来再看一遍读数。
                    // 现在设置项在前，只读读数挪到最后并标为「只读」，同时给出名片页入口。
                    tempCodeCard
                    policyCard
                    entriesCard
                    overviewCard
                    dangerCard
                }
            }
            .padding(.top, V.Page.topSpace)
        }
        .background(V.C.bg.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("锁设置")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .sheet(isPresented: $showSafeMode) { NavigationStack { SafeModeScreen() } }
        .alert("清空全部密码？", isPresented: $clearConfirm) {
            Button("取消", role: .cancel) { clearTyped = "" }
            Button("清空密码", role: .destructive) {
                if clearTyped == "清空" { Task { await runClearPwd() } }
            }
        } message: {
            Text("会把这把锁里的所有密码作废（指纹保留），本机密码台账同时清空。这一步不可撤销，请键入「清空」两个字确认。")
        }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
                            // 2026-11-03（全维度整理）：标题交给系统导航栏。
            Text(app.lock.map { "\($0.name) · \($0.model)" } ?? "还没有门锁")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁可设置")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("锁设置改的是具体一把锁的锁端策略：先添加并配对门锁，再回这一页。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 概览（设备信息 / 容量族 / Boot / 键盘版本 / 电池档案入口）

    private var overviewCard: some View {
        let kc = app.currentKeychain
        let snap = DB.readStatus(mac)
        let st = status
        let firmware: String = {
            if let f = st?.firmware, !f.isEmpty { return f }
            if let f = kc?.fw, !f.isEmpty { return f }
            return "未知"
        }()
        let bootText = (st?.verDFU ?? 0) > 0 ? "\(st?.verDFU ?? 0)" : "该固件未上报"
        let keyboardText = (st?.verKeyboard ?? 0) > 0 ? "\(st?.verKeyboard ?? 0)" : "该固件未上报"
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                // 同一批读数在「锁信息名片」页更全（含绑定时间 / 链路验证 / 电量采样）。
                // 这里保留是为了"改设置时顺手能看一眼"，所以标明只读并指路。
                VCardHeader(title: "这台锁 · 只读")
                VValueRow(label: "型号", value: PidMap.productName(kc?.pid ?? 0), mono: false)
                VRowDivider()
                VValueRow(label: "固件", value: firmware)
                VRowDivider()
                VValueRow(label: "Boot 版本", value: bootText)
                VRowDivider()
                VValueRow(label: "键盘版本", value: keyboardText)
                VRowDivider()
                VValueRow(label: "密码容量", value: capacityText(used: (snap?.pwdCap ?? 0) - (snap?.pwdStock ?? 0), cap: snap?.pwdCap ?? 0))
                VRowDivider()
                VValueRow(label: "指纹容量", value: capacityText(used: (snap?.fpCap ?? 0) - (snap?.fpStock ?? 0), cap: snap?.fpCap ?? 0))
                VRowDivider()
                VValueRow(label: "锁钟偏差", value: driftText(st))
                VRowDivider()
                VValueRow(label: "电量", value: batteryText(snap))
                VRowDivider()
                VOutlineButton(title: "重新读取锁状态", systemImage: "arrow.clockwise") {
                    Task { await load(force: true) }
                }
                VOutlineButton(title: "查看完整锁信息名片", systemImage: "info.circle") {
                    router.request(.dest(.deviceInfo))
                }
                .disabled(busy)
                HStack(spacing: V.S.gapS) {
                    if busy {
                        ProgressView().controlSize(.small).tint(V.C.blue)
                        Text("正在与门锁通信…").font(V.F.footnote).foregroundStyle(V.C.text3)
                    } else if let outcome {
                        // 2026-11-03（全维度整理）：原来成功/失败都是同一行灰字，
                        // "解析数据失败"看着像普通说明。失败要走警示色 + 状态点。
                        VStatusLine(tone: outcomeIsFailure ? .attention : .neutral, text: outcome)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    /// 2026-11-04（同名双份 · 已漂移）：`DeviceInfoScreen` 里有一份同名实现，
    /// 它对"容量未读"的写法是「已用 N · 容量未读」—— **保留了用量**；这一份只写「容量未读」，
    /// 把一个已经读到的数字丢掉了。两处统一到信息更多的那种。
    private func capacityText(used: Int, cap: Int) -> String {
        cap > 0 ? "\(max(used, 0)) / \(cap)" : "已用 \(max(used, 0)) · 容量未读"
    }

    private func driftText(_ st: LockStatus?) -> String {
        // 0 = 锁端没回时钟 —— 不能拿它算偏差（会得到 ≈ -531260264 秒，正是用户报过的那个数字）。
        guard let t = st?.lockTime, t > 0 else { return "未读到锁钟" }
        let dev = Int(t - ZKProtocol.nowProtoSeconds())
        if dev == 0 { return "与手机一致" }
        return (dev > 0 ? "+" : "") + "\(dev) 秒"
    }

    private func batteryText(_ snap: StatusSnapshotData?) -> String {
        let p = BatteryCare.displayPct(mac, snapshot: snap?.powerLevel ?? -1)
        return BatteryCare.faceText(p)
    }

    // MARK: - 临时码开关（cmd19）

    private var tempCodeCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "动态密码")
                Text("开通后，锁端按周期接受动态密码；关闭则所有动态码立即失效。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VToggleRow(title: "开通动态密码", detail: otpOn ? "已开通 · 锁端会接受动态码" : "已关闭 · 动态码不会被锁接受", isOn: Binding(
                    get: { otpOn },
                    set: { on in writeOtp(on) }
                ))
                if otpOn {
                    VOutlineButton(title: "生成动态密码", systemImage: "clock.badge.questionmark") {
                        router.request(.dest(.zotp))
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 锁端策略：静音 / 防尾随 / 安全模式

    private var policyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁端策略")
                VToggleRow(title: "静音", detail: muted ? "开 · 键盘与开锁不提示音" : "关 · 正常提示音", isOn: Binding(
                    get: { muted },
                    set: { on in writeMuted(on) }
                ))
                VRowDivider()
                VValueRow(label: "防尾随 / 自动上锁", value: "\(autoLock) 秒", note: "电控开锁后等待几秒自动上锁；2–6 秒可调。")
                VOutlineButton(title: "设置防尾随等待时长", systemImage: "figure.walk.arrival") {
                    router.request(.dest(.tailgate))
                }
                .disabled(!canTailgate)
                VRowDivider()
                VValueRow(label: "安全模式", value: safeModeText, note: "A 模式单验、B 模式双验；切换要连上锁并回读确认。")
                VOutlineButton(title: "打开安全模式说明", systemImage: "lock.rotation") {
                    showSafeMode = true
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var canTailgate: Bool {
        guard let kc = app.currentKeychain else { return false }
        return PidMap.canTailgate(kc.pid, fw: kc.fw)
    }

    private var safeModeText: String {
        guard let st = status else { return "未读到" }
        if st.verifyMode == 1 && st.broadcastMode != 0 { return "B · 双验" }
        if st.verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    // MARK: - 入口

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            // 2026-11-03（全维度整理）：这里原来 6 项，其中 3 项（锁信息名片 / 校准门锁时间 /
            // 固件升级）在「门」页或设置页已有入口 —— 同一目的地三个入口。只留**仅此处可达**的
            // 3 个（电池档案 / 锁档案 / 全部锁），其余走门页。
            Text("更多").font(V.F.section).foregroundStyle(V.C.text1)
            VCard {
                VStack(spacing: 0) {
                    VListRow(title: "电池档案", detail: "电量采样 / 五档 / 电池型号与换电日期", systemImage: "battery.75percent", tint: V.C.rewardGreen) {
                        router.request(.dest(.batteryProfile))
                    }
                    VDivider()
                    VListRow(title: "锁档案", detail: "昵称 / 符号 / 色标 / 分组 / 解锁 PIN", systemImage: "lock.rectangle", tint: V.C.purple) {
                        router.request(.dest(.lockProfile))
                    }
                    VDivider()
                    VListRow(title: "全部锁", detail: "多锁统计 / 分组 / 排序", systemImage: "square.stack.3d.up", tint: V.C.miniBlue) {
                        router.request(.dest(.lockPortfolio))
                    }
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    // MARK: - 危险区：清空全部密码（0A delAlias=FFFF）

    private var dangerCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "危险操作", showsChevron: false)
                Text("清空全部密码会把锁里所有密码作废（指纹保留），并同时清空本机密码台账。清空后需要重新逐条添加。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VTextFieldRow(label: "键入「清空」确认", text: $clearTyped, placeholder: "清空")
                VOutlineButton(title: "清空全部密码", systemImage: "delete.left", tint: V.C.red) {
                    clearConfirm = true
                }
                .disabled(clearTyped != "清空" || busy || !canClearPwd)
                .opacity(clearTyped == "清空" ? 1 : 0.45)
                if !canClearPwd {
                    Text("这把锁的型号不支持清空密码。").font(V.F.footnote).foregroundStyle(V.C.text3)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var canClearPwd: Bool {
        guard let kc = app.currentKeychain else { return false }
        return PidMap.canClearPwd(kc.pid)
    }

    // MARK: - 读

    private func load(force: Bool = false) async {
        guard !mac.isEmpty, !busy else { return }
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
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            outcomeIsFailure = true
        }
    }

    // MARK: - 写

    private func writeOtp(_ on: Bool) {
        // E-07：进函数先把 MAC 固定成局部常量。mac 是计算属性（app.lock?.id），
        // await 期间用户换锁会让结果写到新锁的 kf_otp_ 键上。
        let mac = self.mac
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        Task {
            defer { busy = false }
            do {
                try await LockService.shared.ensureConnected(mac: mac)
                try await LockService.shared.setZotp(on)
                DB.saveOtpStatus(mac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                otpOn = on
                outcome = on ? "动态密码已开通" : "动态密码已关闭"
                outcomeIsFailure = false
                AppToast.shared.show(outcome ?? "", tone: .ok)
            } catch {
                otpOn = !on
                outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                outcomeIsFailure = true
            }
        }
    }

    private func writeMuted(_ on: Bool) {
        // E-07：同上 —— 静音位写到错误的锁是"用户以为给 A 静音，实际是 B 静音"。
        let mac = self.mac
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        Task {
            defer { busy = false }
            do {
                // 2026-11-01 修复：原来这里自己 `LockService.setSilent` + `DB.store.set`，
                // **绕过了 `AppModel.setMuted`** —— 而后者会 `await refreshStatus()` 刷新投影。
                // 于是这一页切了静音后，`LockStatusScreen`（读 `app.lock.muted`）仍显示旧状态，
                // 直到下次有人手动重读状态。改走 AppModel 那条唯一路径。
                let r = await app.setMuted(on)
                if case .failure(let e) = r { throw e }
                muted = on
                outcome = on ? "已静音：键盘与开锁不提示音" : "已恢复提示音"
                outcomeIsFailure = false
            } catch {
                muted = !on
                outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                outcomeIsFailure = true
            }
        }
    }

    private func runClearPwd() async {
        let mac = self.mac   // E-07：await 期间换锁不能把清空动作落到另一把锁的台账
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        outcomeIsFailure = false
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdClear()
            var l = DB.ledger(mac)
            l.pwds = []
            DB.saveLedger(mac, l)
            app.reloadKeys(mac)
            clearTyped = ""
            outcome = "已清空全部密码（指纹保留）"
            outcomeIsFailure = false
            AppToast.shared.show("已清空全部密码", tone: .ok)
        } catch {
            outcome = "清空失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            outcomeIsFailure = true
        }
    }
}

#Preview("LockSettingsScreen") {
    NavigationStack { LockSettingsScreen() }
        .environment(AppModel())
        .environment(Router())
}
