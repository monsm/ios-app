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

    @State private var otpOn = false
    @State private var code = ""
    @State private var window = ""
    @State private var busy = false
    @State private var outcome: String?

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
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("动态密码")
        .navigationBarTitleDisplayMode(.inline)
        .task { otpOn = DB.otpStatus(mac)?.on ?? false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("动态密码")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("ZOTP · 6 位数字，按锁端周期自动更换")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
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
                VCardHeader(title: "锁端开关 · 命令 19")
                VToggleRow(title: "开通临时密码", detail: otpOn ? "锁端会接受 ZOTP 动态码" : "关闭状态下生成的码不会被锁接受", isOn: Binding(
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
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "当前动态码", showsChevron: false)
                Text(code.isEmpty ? "······" : code)
                    .font(V.F.sans(AXSettings.bigOTP ? 44 : 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(V.C.text1)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, V.S.gapM)
                    .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.card, style: .continuous))
                    .accessibilityLabel(code.isEmpty ? "还没有生成动态密码" : "动态密码 \(code)")
                if !window.isEmpty {
                    Text("于 \(window) 失效，失效前仅可使用一次")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }
                HStack(spacing: V.S.gapS) {
                    VActionButton(title: busy ? "生成中…" : "生成动态密码", systemImage: "clock.badge.questionmark") {
                        generate()
                    }
                    .disabled(busy)
                }
                if !code.isEmpty {
                    VOutlineButton(title: "复制到剪贴板", systemImage: "doc.on.doc") {
                        Clip.set(code)
                        outcome = "已复制动态密码"
                    }
                }
                if let outcome {
                    Text(outcome).font(V.F.footnote)
                        .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var helpCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "使用须知", showsChevron: false)
                Text("· 生成前请先校准门锁时间（偏差 > 180 秒会导致锁侧校验失败）。")
                Text("· 周期取锁端上报的 zotpPeriod（缺省 30 分钟）；同一窗口最多 100 个，超出请等下一个窗口。")
                Text("· 只有 A 模式（单验）下临时密码才有效；B 模式下请改用密码或指纹。")
            }
            .font(V.F.footnote)
            .foregroundStyle(V.C.text3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func writeEnable(_ on: Bool) {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await LockService.shared.ensureConnected(mac: mac)
                try await LockService.shared.setZotp(on)
                DB.saveOtpStatus(mac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                otpOn = on
                outcome = on ? "已开通临时密码" : "已关闭临时密码"
            } catch {
                otpOn = !on
                outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
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
