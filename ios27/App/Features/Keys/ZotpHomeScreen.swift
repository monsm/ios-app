// ZotpHomeScreen.swift —— 动态密码（V8 设计语言）
//
// 与 ZotpScreen 的能力对齐：开通 cmd19 → 按锁端周期生成 6 位动态码 → 显示失效时刻并可复制；
// 防窥挡片（长按揭开、松手复位）、双击切换字号、录屏遮挡。
import SwiftUI

struct ZotpHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var otpOn = false
    @State private var code = ""
    @State private var window = ""
    @State private var busy = false
    @State private var outcome: String?
    @State private var shieldOn = false
    @State private var revealed = false
    @State private var bigCode = false

    private var mac: String { app.lock?.id ?? "" }
    private var kc: Keychain? { app.currentKeychain }

    /// 距离本窗口失效还有多少秒。
    ///
    /// 2026-11-05（用户指令：减少文字、图形化变多）：本页是全仓最后几个「零视觉」页面之一，
    /// 而动态码页**本该有失效倒计时**。窗口语义与 ZOTP.nextWindow 完全一致：30 分钟一档。
    private func secondsToExpiry(at now: Date) -> Int {
        let cal = WeekCal.gregorian
        let m = cal.component(.minute, from: now)
        let sec = cal.component(.second, from: now)
        return max(0, 30 * 60 - (m % 30) * 60 - sec)
    }

    /// 倒计时环：TimelineView 每秒重绘，**不需要 @State + Timer**（纯 SwiftUI，
    /// 没有需要手动维护的失效点）。剩余不足 2 分钟转警告色。
    private var expiryRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remain = secondsToExpiry(at: ctx.date)
            let fraction = Double(remain) / (30.0 * 60.0)
            VStack(spacing: V8.S.gapXS) {
                VHalfRing(
                    fraction: fraction,
                    center: String(remain / 60) + ":" + String(format: "%02d", remain % 60),
                    tint: remain < 120 ? V8.C.warn : V8.C.accent,
                    size: V8.G.heroRingInline
                )
                Text("距失效")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("距本窗口失效的倒计时")
        // 2026-11-05（全技能审核 · VoiceOver）：原来只报「倒计时」，剩余时间对读屏用户
        // 完全不存在 —— 而倒计时环就是这页唯一的信息图形。补 accessibilityValue。
        .accessibilityValue({
            let remain = secondsToExpiry(at: Date())
            return "剩余 " + String(remain / 60) + " 分 " + String(remain % 60) + " 秒"
        }())
    }

    private var judgement: String {
        if app.lock == nil || kc == nil { return "还没有门锁" }
        if !otpOn { return "动态密码还没开通" }
        if code.isEmpty { return "可以生成动态码" }
        return "这枚码只用一次"
    }

    private var lead: String {
        if app.lock == nil || kc == nil {
            return "动态密码要用这把锁的钥匙串现场计算：先在「添加门锁」配对，再回来生成。"
        }
        // 2026-11-05（截图审查 · 文案不通）：没有码的时候原来会渲染成「于 下一窗口 失效。」——
        // 一句读不通的话。没码只说周期，有码才说几点失效。
        if window.isEmpty { return "6 位数字 · 按锁端周期自动更换。" }
        return "6 位数字 · 按锁端周期自动更换 · 于 \(window) 失效。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if app.lock == nil || kc == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "动态密码要用这把锁的钥匙串现场计算：先添加并配对门锁，再回来生成。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                enableCard
                if otpOn { generateCard }
                helpCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .task {
            otpOn = DB.otpStatus(mac)?.on ?? false
            shieldOn = DB.store.getBool("kf_otp_shield", false)
        }
    }

    private var enableCard: some View {
        VCard2 {
            VCardHead(eyebrow: "锁端开关", statement: otpOn ? "已开通" : "已关闭")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Toggle(isOn: Binding(get: { otpOn }, set: { on in writeEnable(on) })) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("开通动态密码")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text(otpOn ? "锁端会接受动态码" : "关闭状态下生成的码不会被锁接受")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                }
            }
            .frame(minHeight: V8.H.min)
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var generateCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当前动态码", statement: code.isEmpty ? "还没生成" : "有效")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if code.isEmpty {
                // 卡头已写「还没生成」，这里只给下一步，不重复状态。
                VEmptyHint(text: "点下面的按钮取一枚")
                    .padding(.vertical, V8.S.gapL)
            } else {
                Text(displayCode)
                    // 「无障碍 · 放大临时码」的消费点：开启后默认就用 62pt 档；双击仍可临时切换。
                    .font((bigCode || DB.store.getBool("kf_ax_bigotp")) ? V8.T.hero : V8.T.heroL)
                    .monospacedDigit()
                    .foregroundStyle(V8.C.ink1)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, V8.S.gapL)
                    .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                    .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                        if shieldOn { revealed = pressing }
                    }, perform: { })
                    .onTapGesture(count: 2) { bigCode.toggle() }
                    .accessibilityLabel(shieldOn && !revealed ? "动态密码已遮挡，长按揭开" : "动态密码 \(code)")
                    // 2026-11-05（全技能审核 · VoiceOver）：长按/双击是手势专用路径，
                    // 读屏用户无法执行 —— 用 accessibilityAction 暴露同样的能力。
                    .accessibilityAction(named: "揭开动态密码") { revealed = true }
                    .accessibilityAction(named: "切换字号") { bigCode.toggle() }
                    .captureShield("这是一枚可开门的动态码\n屏幕正在被录制或截图，已遮挡")
            }
            if shieldOn && !code.isEmpty {
                Text(revealed ? "松开手指会重新遮住" : "长按可揭开挡片 · 双击可切换字号")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
            }
            if !window.isEmpty {
                // 2026-11-05（图形化）：原来这里是一行「于 HH:MM 失效，失效前仅可使用一次」，
                // 换成倒计时环 —— 同样的信息，形状更快，而且是动态的。
                HStack(spacing: V8.S.gapL) {
                    expiryRing
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        Text("于 \(window) 失效")
                            .font(V8.T.value)
                            .foregroundStyle(V8.C.ink1)
                        Text("失效前仅可使用一次")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ink4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, V8.S.gapS)
            }
            V8ActionButton(title: busy ? "生成中…" : "生成动态密码", style: .primary, busy: busy) {
                generate()
            }
            .disabled(busy || generateBlockedReason != nil)
            .padding(.top, V8.S.gapM)
            if let why = generateBlockedReason {
                Text(why)
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !code.isEmpty {
                VNavRow(title: "复制到剪贴板", detail: nil) {
                    Clip.set(code)
                    outcome = "已复制动态密码"
                }
                .padding(.top, V8.S.gapS)
            }
            VDivider2()
                .padding(.vertical, V8.S.gapS)
            Toggle(isOn: Binding(get: { shieldOn }, set: { on in
                shieldOn = on
                DB.store.set("kf_otp_shield", on)
                if !on { revealed = false }
            })) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("防窥挡片")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text("开启后动态码默认显示为圆点，长按才揭开；松手复位。旁边有人时更安全。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: V8.H.min)
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helpCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "怎么用", statement: "三条规则")
            Text("· 动态码只在开通过后有效：锁端开关关掉时，生成的码不会被锁接受。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
            Text("· 同一 30 分钟窗口最多 100 个；生成失败不占用名额。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
            Text("· 只有 A 模式（单验）下动态密码才有效；B 模式（双验）下请改用固定密码或指纹开门。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
        }
    }

    private var displayCode: String {
        if code.isEmpty { return "······" }
        if shieldOn && !revealed { return "••••••" }
        return code
    }

    private func writeEnable(_ on: Bool) {
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
        // 2026-11-05（对抗审查 · 去重复判据）：这里原来把 generateBlockedReason 的两条判据
        // **又写了一遍**（同样的 skey 长度检查、同样的 100 上限、同样的两句文案）。
        // 同一个规则两处各判一次 ⇒ 改一处忘另一处就会分叉（本仓已经栽过一回：开锁方式分类）。
        // 现在按钮禁用依据就是这里的前置条件，单一来源。
        if let blocked = generateBlockedReason {
            outcome = blocked
            return
        }
        let win = ZOTP.nextWindow()
        let current = DB.otpIdx(mac)
        let idx = (current?.invalidTime == win) ? (current?.idx ?? -1) + 1 : 0
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
