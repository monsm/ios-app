// AutoOpenHomeScreen.swift —— 靠近自动开锁（V8 设计语言）
//
// 与 AutoOpenScreen 的能力对齐：主开关（默认关、fail-closed）、风险披露、面容确认两档、
// 距离标定（真采 5 次链路 RSSI 取 P95）与清除、「上次没自动开的原因」。
// 只改渲染层：开关仍写 kf_autoopen / kf_autoopen_face（AutoOpen.on / AutoOpen.faceTier），
// 标定仍走 LockService.ensureConnected + BLEService.readLinkRSSI + AutoOpen.saveAutocal / clearAutocal。
//
// 两处刻意差异：
//   ① 空壳模式下整页只读：开关会真的改变「门会不会自己开」，标定会写这把锁的真实 kf_autocal_<mac>；
//      旧页在空壳里照样能改 —— 空壳的纪律是只隐藏、不破坏。
//   ② 开启主开关改成「先确认再开」：这是唯一一个不需要你动手就会开门的功能，旧页点一下 Toggle 就直接生效。
import SwiftUI

struct AutoOpenHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var store: SettingsStore { SettingsStore.shared }

    @State private var calibrating = false
    /// 标定失败时给用户看的原因。旧实现用 try? await 把连不上静默吞掉，用户只看到转圈。
    @State private var calibrationError: String?
    /// 开启前的一次确认（风险披露已在卡内常驻，这里只做「确实要开」的确认）。
    @State private var confirmEnable = false

    private var decoyed: Bool { DB.isDecoy }

    private var on: Bool { AutoOpen.on }

    private var faceTier: FaceConfirmTier { AutoOpen.faceTier == 0 ? .free : .strict }

    private var calibrationAt: Int64? {
        guard let cal = AutoOpen.autocal(app.lock?.id ?? "") else { return nil }
        return Int64(cal.at * 1000)
    }

    private var lastSkipReason: String? {
        AutoOpen.lastReject(app.lock?.id ?? "")?.reason
    }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下自动开锁只读" }
        guard on else { return "关闭 · 走到门前仍需手动开锁" }
        guard app.lock?.isConnected == true else { return "已开启 · 但锁未连接" }
        return "已开启 · " + faceTier.title
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。自动开锁可以看，但这一屏不写入 —— 退出空壳后再调。"
        }
        guard on else {
            return "开启后，App 在前台且靠近门时会自动下发开锁 —— 这是唯一一个不需要你动手就会开门的功能，所以默认关。"
        }
        return "只在 App 在前台时生效；布防时段内、以及防拆事件之后，自动开锁会被自动关掉。"
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
            } else {
                mainCard
                if app.lock == nil {
                    noLockCard
                } else if on {
                    confirmCard
                    calibrationCard
                    rejectCard
                } else {
                    offCard
                }
                if app.trialGuard { trialCard }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .onAppear(perform: syncAutoOpenState)
        .v8Confirm(
            isPresented: $confirmEnable,
            title: "开启靠近自动开门？",
            consequence: "开启后，App 在前台且你走近门时会在不点任何按钮的情况下下发开锁。默认档只认「手机已解锁 + App 在前台」—— 别人拿你已解锁的手机走近门锁，也可能替你开门。这一步可以撤销：随时关掉主开关。",
            confirmTitle: "开启",
            isDestructive: false
        ) {
            setAutoOpen(true)
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                // 2026-11-05（截图审查）：这枚芯片与**首屏第一张卡**的卡头同值，删掉。
                // 下面两枚（确认档 / 标定）**保留** —— 它们对应的卡在折叠线以下，
                // 用户不滚动看不到，这正是芯片该承载的（与安全页整排删除的判据同源：
                // 芯片只承载「默认折叠、需要滚动才看得到」的状态）。
                VChip2(
                    icon: .ring(faceTier == .strict ? 1 : 0.5, faceTier == .strict ? V8.C.warn : V8.C.ink3),
                    label: "确认档",
                    value: faceTier.title
                )
                VChip2(
                    icon: .ring(calibrationAt == nil ? 0.02 : 1, calibrationAt == nil ? V8.C.warn : V8.C.ok),
                    label: "标定",
                    value: calibrationAt == nil ? "未标定" : "已校准"
                )
                VChip2(
                    icon: .glyph(lastSkipReason == nil ? "questionmark.circle" : "exclamationmark.circle"),
                    label: "上次",
                    value: lastSkipReason == nil ? "无记录" : "有原因"
                )
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "靠近自动开锁", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这一屏既不显示也不写入自动开锁的开关与标定 —— 开关会真的改变「门会不会自己开」，标定会写这把锁的真实门槛。")
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

    // MARK: - 卡 1 主开关

    private var mainCard: some View {
        VCard2 {
            // 2026-11-05（截图审查 · 设计冗余）：本页同一状态被说了四遍 ——
            //   页标题「关闭 · 走到门前仍需手动开锁」/ 芯片「主开关 关」/
            //   这里的卡头「走近自动开门 关闭」/ toggle 标题「走近自动开门」。
            // 卡头只报状态（开关名由 toggle 承载）。
            // 2026-11-05（全技能审核 · 同屏三重复）：页标题「关闭 · 走到门前仍需手动开锁」、
            // 卡头「关闭」、下面「自动开锁 关」说的是同一件事。卡头只留开关名，
            // 状态由 Toggle 与那一行读数承载。
            VCardHead(eyebrow: "主开关", statement: "走近自动开门")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: autoOpenBinding) {
                Text("开启后自动下发开锁")
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapS)
            // 2026-11-05（全技能审核 · 设计冗余）：页标题「关闭 · 走到门前仍需手动开锁」
            // 已说清关闭后果，卡内再写一遍同义句是第四遍。删掉，保留分隔线与门控段。
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "自动开锁", tagTint: on ? V8.C.ok : V8.C.ink4, title: on ? "开" : "关", value: "")
                VDotRule()
                VDataRow(tag: "连接", tagTint: app.lock?.isConnected == true ? V8.C.ok : V8.C.warn,
                         title: app.lock?.isConnected == true ? "锁已连接" : "锁未连接", value: "")
            }
            .padding(.top, V8.S.gapS)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text(AutoOpen.riskDisclosure)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.warn)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("门控边界：只在 App 在前台时生效；布防时段内、以及防拆事件之后，自动开锁会被自动关掉 —— 这些否决不给你留提示，所以下面会记「上次没自动开的原因」。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空态：还没有门锁

    private var noLockCard: some View {
        VEmpty(
            title: "添加一把门锁",
            reason: "自动开锁要挂在具体一把锁上；距离标定也要连上锁读信号。先添加门锁，再回来开启。",
            actionTitle: "添加门锁"
        ) { router.request(.dest(.addLock)) }
    }

    // MARK: - 卡 2 关闭时的说明

    private var offCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "现在", statement: "走到门前，App 不会替你开门")
            Text("下一步：如果确实想要「走到门口就开」，把上面的开关打开。打开后建议先做一次距离标定 —— 不标定的话，门内经过也会触发。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "去门页手动开锁", detail: "开锁只在门页的刻度盘上") {
                router.select(.door)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 3 面容确认

    private var confirmCard: some View {
        VCard2 {
            VCardHead(eyebrow: "确认档", statement: faceTier.title)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VHScroll {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(FaceConfirmTier.allCases) { item in
                        selectChip(item.title, on: faceTier == item) { setFaceTier(item) }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.top, V8.S.gapM)
            Text(faceTier.note)
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-11-05（值级重复）：档位名在卡头 statement、选中芯片、这一行里出现了三次。
            // 卡头 + 芯片已经说清，删掉这一行。
        }
    }

    // MARK: - 卡 4 距离标定

    private var calibrationCard: some View {
        VCard2 {
            VCardHead(eyebrow: "距离标定", statement: calibrationAt == nil ? "未标定（默认门槛）" : "已校准")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "上次标定", tagTint: V8.C.ink4,
                         title: calibrationAt.map { TimeFormat.dayShort($0) } ?? "未标定", value: "")
                VDotRule()
                VDataRow(tag: "触发距离", tagTint: V8.C.ink4,
                         title: calibrationAt == nil ? "默认（-40 dBm）" : "已校准", value: "")
            }
            .padding(.top, V8.S.gapS)
            Text("标定方式：站在门外约一步的位置，点下面的按钮，App 会记下那一刻的信号强度作为门槛。没标定就打开自动开锁，门内走动也可能触发。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if calibrating {
                VBusy(text: "正在采集信号 · 请保持站在门外")
                    .padding(.top, V8.S.gapM)
            } else {
                Button {
                    calibrate()
                } label: {
                    Text(calibrationAt == nil ? "开始标定" : "重新标定")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(V8PressStyle())
                .padding(.top, V8.S.gapM)
                .accessibilityLabel(calibrationAt == nil ? "开始标定" : "重新标定")
                if calibrationAt != nil {
                    Button {
                        guard let mac = app.lock?.id else { return }
                        AutoOpen.clearAutocal(mac)
                        calibrationError = nil
                    } label: {
                        Text("清除标定（回到默认门槛）")
                            .font(V8.T.tab)
                            .foregroundStyle(V8.C.ink1)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: V8.H.min)
                            .overlay(
                                RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                                    .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                            )
                    }
                    .buttonStyle(V8PressStyle())
                    .padding(.top, V8.S.gapS)
                    .accessibilityLabel("清除标定")
                }
            }
            if let calibrationError {
                VFailure(what: "标定没有完成", why: calibrationError, next: "站到门外一步的位置、保持手机朝向门锁，再试一次；旧门槛已按上面的说明处理。")
                    .padding(.top, V8.S.gapM)
            }
        }
    }

    // MARK: - 卡 5 上次没自动开的原因

    private var rejectCard: some View {
        VCard2 {
            VCardHead(eyebrow: "上一次", statement: lastSkipReason == nil ? "还没有「没自动开」的记录" : "有一次被否决")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let reason = lastSkipReason {
                VDataRow(tag: "原因", tagTint: V8.C.warn, title: reason, value: "")
                    .padding(.top, V8.S.gapS)
                Text("这条是这次没自动开的原因。想看每一次的开锁结果，去台账页。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("走到门前没开门时，这里会写清原因（信号太弱 / 在布防时段 / 面容未通过）。现在还没有这样的记录 —— 说明自动开锁还没被否决过。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 只读试验模式

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "自动开锁不会真的下发")
            Text("只读试验模式拦的是下发到门锁的写命令 —— 自动开锁用的正是这条链路，所以靠近时会被拦下、门不会开。距离标定只读链路 RSSI、不下发写命令，仍可标定。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func setAutoOpen(_ value: Bool) {
        guard !DB.isDecoy else { return }
        store.autoOpenEnabled = value
        AutoOpen.on = value
    }

    private var autoOpenBinding: Binding<Bool> {
        Binding(
            get: { AutoOpen.on },
            set: { value in
                if value {
                    // 先确认再开：不在 Toggle 的 setter 里直接落盘。
                    confirmEnable = true
                } else {
                    setAutoOpen(false)
                }
            }
        )
    }

    private func setFaceTier(_ value: FaceConfirmTier) {
        guard !DB.isDecoy else { return }
        store.faceConfirm = value
        AutoOpen.faceTier = (value == .strict) ? 1 : 0
    }

    private func calibrate() {
        guard let mac = app.lock?.id, !calibrating else { return }
        guard !DB.isDecoy else {
            calibrationError = "空壳模式下不标定 —— 标定会写入这把锁的真实门槛。"
            return
        }
        calibrating = true
        calibrationError = nil
        Task { @MainActor in
            defer { calibrating = false }
            // 真链路：连上锁后读 5 次当前链路 RSSI，取 P95 作为这把锁的距离门槛。
            // 连不上必须说出来：旧实现用 try? 吞掉，用户只看到转圈然后什么都没变。
            do {
                try await LockService.shared.ensureConnected(mac: mac)
            } catch {
                calibrationError = "连不上门锁，没法标定：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }
            var samples: [Int] = []
            for _ in 0 ..< 5 {
                let r: Int? = await withCheckedContinuation { cont in
                    BLEService.shared.readLinkRSSI(timeoutMs: 1200) { cont.resume(returning: $0) }
                }
                if let r { samples.append(r) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if AutoOpen.saveAutocal(mac, samples: samples) != nil {
                calibrationError = nil
            } else {
                // 标定失败必须清掉旧门槛：否则界面说「没标定」，实际还在用上一次的值。
                AutoOpen.clearAutocal(mac)
                calibrationError = "这次只采到 \(samples.count)/5 个信号样本，不足以标定。旧门槛已清除，会回落到默认档；请站在门外一步的位置、保持手机朝向门锁，再试一次。"
            }
        }
    }

    private func syncAutoOpenState() {
        store.autoOpenEnabled = AutoOpen.on
        store.faceConfirm = faceTier
    }

    // MARK: - 行构件

    private func selectChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
