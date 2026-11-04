// ZotpScreen.swift —— 动态临时密码（ZOTP）。
//
// 来源：原 App/UI/CredentialOtp.swift（临时密码卡片与生成/停用，genOtp / toggleAlerts 同源）
//   与 App/Core/ZOTP.swift（6 位码 = AES(skey, 时间计数器 + MAC 反序 + idx)）。
// 这屏干什么：开通 cmd19 → 按锁端上报的周期生成 6 位动态码 → 显示窗口失效时刻并可复制；
//   同一 30 分钟窗口最多 100 个，生成失败不会占用名额。
// 数据从哪来：DB.otpStatus / DB.otpIdx / DB.readStatus(mac).zotpPeriod。
// 主动作：「生成动态密码」。
import SwiftUI

struct ZotpScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var otpOn = false
    @State private var code = ""
    @State private var window = ""
    @State private var busy = false
    @State private var outcome: String?
    /// 防窥挡片（原 CredentialOtp.swift:86-108）：默认关；开着时长按才揭开。
    @State private var shieldOn = false
    @State private var revealed = false
    @State private var bigCode = false

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if app.lock == nil || kc == nil {
                    noLockCard
                } else {
                    enableCard
                    if otpOn { generateCard }
                    helpCard
                }
            }
            .padding(.top, V.Page.topSpace)
        }
        .background(V.C.bg.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("动态密码")
        .navigationBarTitleDisplayMode(.large)
        .task {
            otpOn = DB.otpStatus(mac)?.on ?? false
            shieldOn = DB.store.getBool("kf_otp_shield", false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
                            // 2026-11-03（全维度整理）：标题交给系统导航栏（大标题），页内不再自绘。
            Text("6 位数字 · 按锁端周期自动更换")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁").font(V.F.displayB).foregroundStyle(V.C.text1)
                Text("动态密码要用这把锁的钥匙串现场计算：先在「添加门锁」配对，再回来生成。")
                    .font(V.F.body).foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var enableCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁端开关")
                VToggleRow(title: "开通动态密码", detail: otpOn ? "锁端会接受动态码" : "关闭状态下生成的码不会被锁接受", isOn: Binding(
                    get: { otpOn },
                    set: { on in writeEnable(on) }
                ))
                if let outcome {
                    Text(outcome).font(V.F.footnote).foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var generateCard: some View {
        // SEC-11：整张卡（含动态码）在录屏/截图时被遮挡 —— 修饰符必须包住真正敏感的内容，
        // 不能挂在旁边的空视图上（那是假实现）。
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "当前动态码", showsChevron: false)
                // 2026-11-03（整页截图实测）：没生成过时 displayCode 返回六个中点「······」——
                // 与"防窥遮挡"的「••••••」几乎一样，用户分不清"还没生成"和"生成了但被遮住"。
                // 未生成时改说人话；只有真的被遮挡时才用圆点。
                if code.isEmpty {
                    Text("还没有生成 —— 点下面的按钮取一枚")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, V.S.gapM)
                } else {
                    Text(displayCode)
                        .font(((AXSettings.bigOTP || bigCode) ? V.F.otpBig : V.F.otpRegular).monospacedDigit())
                        .foregroundStyle(V.C.text1)
                        // 减弱动态下不做数字滚动（纯换字）。
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, V.S.gapM)
                        // 2026-11-03（Liquid Glass 审计 · 同心圆角）：外层 VCard 圆角 27、内边距 16.3，
                        // 内块应约 27-16.3 ≈ 10.7；原来又用 V.R.card(27) ⇒ 内外同半径。
                        .background(V.C.cardAlt, in: .rect(cornerRadius: max(0, V.R.card - V.S.cardGutter), style: .continuous))
                        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                            if shieldOn { revealed = pressing }
                        }, perform: {})
                        .onTapGesture(count: 2) { bigCode.toggle() }
                        .accessibilityLabel(shieldOn && !revealed ? "动态密码已遮挡，长按揭开" : "动态密码 \(code)")
                        .accessibilityHint(shieldOn ? "长按揭开挡片，双击切换字号" : "双击切换字号")
                        // SEC-11：码值本体在录屏/截图时被遮挡（修饰符包住的就是这枚码）。
                        .captureShield("这是一枚可开门的动态码\n屏幕正在被录制或截图，已遮挡")
                }
                if shieldOn, !code.isEmpty {
                    Text(revealed ? "松开手指会重新遮住" : "长按可揭开挡片 · 双击可切换字号")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                }
                if !window.isEmpty {
                    Text("于 \(window) 失效，失效前仅可使用一次")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }

                // 2026-11-04（呈现复核 · 同页两处判据不一致）：`generate()` 开头有三条 guard
                // （无锁 / 钥匙串长度不是 32 / 本窗口已用满 100 个），而按钮只按 `busy` 禁用 ——
                // 三条都注定失败的情况，按钮照样可点，点了只弹一句错误。
                // 现在按钮与 guard 同判据，并在按钮下说清为什么不可点。
                HStack(spacing: V.S.gapS) {
                    VActionButton(title: busy ? "生成中…" : "生成动态密码", systemImage: "clock.badge.questionmark") {
                        generate()
                    }
                    .disabled(busy || generateBlockedReason != nil)
                    .opacity((busy || generateBlockedReason != nil) ? 0.45 : 1)
                }
                if let why = generateBlockedReason {
                    Text(why)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !code.isEmpty {
                    VOutlineButton(title: "复制到剪贴板", systemImage: "doc.on.doc") {
                        Clip.set(code)
                        outcome = "已复制动态密码"
                    }
                }
                VRowDivider()
                VToggleRow(
                    title: "防窥挡片",
                    detail: "开启后动态码默认显示为圆点，长按才揭开；松手复位。旁边有人时更安全。",
                    isOn: Binding(
                        get: { shieldOn },
                        set: { on in
                            shieldOn = on
                            DB.store.set("kf_otp_shield", on)
                            if !on { revealed = false }
                        }
                    )
                )
                if let outcome {
                    Text(outcome).font(V.F.footnote)
                        .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var displayCode: String {
        if code.isEmpty { return "······" }
        if shieldOn && !revealed { return "••••••" }
        return code
    }

    private var helpCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "使用须知", showsChevron: false)
                Text("· 生成前请先校准门锁时间：偏差超过 180 秒，锁端会拒绝这个码。")
                Text("· 换码周期由锁端决定（常见 30 分钟）；一个周期内最多取 100 枚，用完请等下一周期。")
                // 2026-11-04（视觉复核 · 用词漂移）：本页标题是「动态密码」，这条须知却叫
                // 「临时密码」—— 同屏两词指同一个东西。另外 B 模式的建议没说"密码"指什么
                // （固定密码），读者可能以为也包括动态码本身（恰恰是 B 模式下无效的那个）。
                Text("· 只有 A 模式（单验）下动态密码才有效；B 模式（双验）下请改用固定密码或指纹开门。")
            }
            .font(V.F.footnote)
            .foregroundStyle(V.C.text3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func writeEnable(_ on: Bool) {
        // E-07：await 期间换锁会把 otpStatus_ 写到另一把锁。
        let mac = self.mac
        guard !mac.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await LockService.shared.ensureConnected(mac: mac)
                try await LockService.shared.setZotp(on)
                DB.saveOtpStatus(mac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                otpOn = on
                outcome = on ? "已开通动态密码" : "已关闭动态密码"
            } catch {
                otpOn = !on
                outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 与 `generate()` 的三条 guard 一一对应：非 nil 即"点了必然失败"。
    private var generateBlockedReason: String? {
        guard let kc else { return "还没有选中门锁" }
        if kc.skey.count != 32 { return "缺少这把锁的钥匙串，无法生成" }
        let win = ZOTP.nextWindow()
        let current = DB.otpIdx(mac)
        let idx = (current?.invalidTime == win) ? (current?.idx ?? -1) + 1 : 0
        if idx > 99 { return "当前窗口已达 100 个上限，请到下一个窗口再生成" }
        return nil
    }

    private func generate() {
        guard !busy, let kc else { return }
        guard kc.skey.count == 32 else {
            outcome = "缺少这把锁的钥匙串，无法生成"
            return
        }
        let win = ZOTP.nextWindow()
        let current = DB.otpIdx(mac)
        let idx = (current?.invalidTime == win) ? (current?.idx ?? -1) + 1 : 0
        guard idx <= 99 else {
            outcome = "当前窗口已达 100 个上限，请到下一个窗口再生成"
            return
        }
        let rawPeriod = DB.readStatus(mac)?.zotpPeriod ?? 0
        let period = rawPeriod > 0 ? rawPeriod : 30
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodMin: period, idx: idx)
        guard !pwd.isEmpty else {
            outcome = "这把锁的 MAC 不是整 6 字节十六进制，已中止生成"
            return
        }
        DB.saveOtpIdx(mac, OtpIdx(idx: idx, invalidTime: win))
        code = pwd
        window = win
        Clip.set(pwd)
        outcome = "已生成并复制（第 \(idx + 1) 个）"
        AppToast.shared.show("动态密码已复制", tone: .ok)
    }
}

#Preview("ZotpScreen") {
    NavigationStack { ZotpScreen() }
        .environment(AppModel())
        .environment(Router())
}
