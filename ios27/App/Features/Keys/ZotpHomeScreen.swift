// ZotpHomeScreen.swift —— 动态密码（V8 设计语言）
//
// 与 ZotpScreen 的能力对齐：开通 cmd19 → 按锁端周期生成 6 位动态码 → 显示失效时刻并可复制；
// 防窥挡片（长按揭开、松手复位）、双击切换字号、录屏遮挡。
import SwiftUI

struct ZotpHomeScreen: View {
    @Environment(AppModel.self) private var app
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
        return "6 位数字 · 按锁端周期自动更换 · 于 \(window.isEmpty ? "下一窗口" : window) 失效。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if app.lock == nil || kc == nil {
                VEmpty(
                    title: "还没有门锁",
                    reason: "动态密码要用这把锁的钥匙串现场计算：先添加并配对门锁，再回来生成。",
                    actionTitle: "添加门锁"
                ) { }
            } else {
                enableCard
                if otpOn { generateCard }
                helpCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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
                Text("还没有生成 —— 点下面的按钮取一枚")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .frame(maxWidth: .infinity)
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
                    .captureShield("这是一枚可开门的动态码\n屏幕正在被录制或截图，已遮挡")
            }
            if shieldOn && !code.isEmpty {
                Text(revealed ? "松开手指会重新遮住" : "长按可揭开挡片 · 双击可切换字号")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
            }
            if !window.isEmpty {
                Text("于 \(window) 失效，失效前仅可使用一次")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
            }
            Button {
                generate()
            } label: {
                Text(busy ? "生成中…" : "生成动态密码")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(busy || generateBlockedReason != nil)
            .opacity((busy || generateBlockedReason != nil) ? 0.45 : 1)
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
