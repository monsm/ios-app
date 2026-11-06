// ZotpScreen.swift —— 锁端动态密码。纯离线计算：skey + MAC + 时间窗口 + 窗口内序号。
//
// 关键口径（与上一版真机验证过的一致）：动态码不是「一直显示在那儿」的实时数字，
// 而是**按次生成**的 —— 锁端认的是「本窗口里的第几个」，所以每生成一次序号加一，
// 并把它记进 `otpIdx_<mac>`。只显示不生成、或拿一个不更新的序号反复算，
// 都会得到一串「看着对、锁不认」的数字 —— 那比报错更坏。
import SwiftUI

@MainActor
struct ZotpScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var enabled = false
    @State private var errorLine: String?
    @State private var code = ""
    @State private var window = ""
    @State private var copied = false

    private var kc: Keychain? { DB.keychainForUnlock(app.currentMac) }

    /// 锁端上报的周期（分钟）。旧快照缺这个键 ⇒ 回落协议默认 30。
    private var period: Int {
        let raw = DB.readStatus(app.currentMac)?.zotpPeriod ?? 0
        return raw > 0 ? raw : 30
    }

    /// 本窗口里下一个该用的序号。换窗口归零；一个窗口最多 100 个。
    private var nextIndex: Int? {
        let win = ZOTP.nextWindow()
        let current = DB.otpIdx(app.currentMac)
        let idx = (current?.invalidTime == win) ? (current?.idx ?? -1) + 1 : 0
        return idx > 99 ? nil : idx
    }

    /// 生成的前置条件只有一个来源 —— 按钮的禁用与提示都看它。
    private var blockedReason: String? {
        guard let kc else { return "还没有选中门锁" }
        if kc.skey.count != 32 { return "缺少这把锁的钥匙串，无法生成" }
        if nextIndex == nil { return "本窗口已经生成满 100 个，等下一个窗口再来" }
        return nil
    }

    /// 本窗口已经用掉几个（还没生成过时是 0）。
    private var usedInWindow: Int {
        let win = ZOTP.nextWindow()
        let current = DB.otpIdx(app.currentMac)
        guard current?.invalidTime == win else { return 0 }
        return (current?.idx ?? -1) + 1
    }

    /// 距离本窗口失效还有多少秒（30 分钟一档，与 ZOTP.nextWindow 同一口径）。
    private func secondsToExpiry(at now: Date) -> Int {
        let cal = WeekCal.gregorian
        let minute = cal.component(.minute, from: now)
        let second = cal.component(.second, from: now)
        return max(0, 30 * 60 - (minute % 30) * 60 - second)
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 动态密码", back: { dismiss() })

            DisplayLine(text: enabled ? "此刻的\n一串数字。" : "让门锁\n自己报数。", size: 36)
                .padding(.top, 16)
            Text(enabled
                 ? "动态密码由门锁和手机各自算出，不经过网络。每 \(period) 分钟换一次，一个窗口内每生成一次就往后排一位。"
                 : "动态密码是锁端按周期报出的 6 位数。开通后，它只在这台手机上算得出来。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            if enabled {
                codeCard
                    .padding(.top, 22)

                PrimaryButton(title: generateTitle, busy: busy, enabled: blockedReason == nil) {
                    generate()
                }
                .padding(.top, 20)

                if let blocked = blockedReason {
                    Text(blocked)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.danger)
                        .padding(.top, 10)
                }

                ReadingRow(items: [
                    (label: "周期", value: "\(period)", unit: "分钟"),
                    (label: "本窗口", value: "\(usedInWindow)", unit: "个"),
                    (label: "失效", value: window.isEmpty ? ZOTP.nextWindow() : window, unit: nil),
                ])
                .padding(.top, 24)

                if !code.isEmpty {
                    HStack(spacing: 10) {
                        GhostButton(title: copied ? "已复制" : "复制这串数字", symbol: copied ? "checkmark" : "doc.on.doc") {
                            Clip.set(code)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        }
                    }
                    .padding(.top, 18)
                }

                Button {
                    Task { await toggle(false) }
                } label: {
                    Text(busy ? "正在关闭…" : "关闭动态密码")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.45 : 1)
                .padding(.top, 16)
            } else {
                enableCard
                    .padding(.top, 22)
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            enabled = DB.otpStatus(app.currentMac)?.on ?? false
        }
    }

    private var generateTitle: String {
        if let idx = nextIndex, idx > 0 {
            return "再生成一个（第 \(idx + 1) 个）"
        }
        return "生成动态密码"
    }

    // MARK: - 码

    private var codeCard: some View {
        DaylightPane(height: 250, showSill: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Kicker(text: "DYNAMIC · 前门", dot: true, tint: T.C.ink2)
                    Spacer()
                    Badge(text: "离线计算")
                }
                Spacer()
                Text(code.isEmpty ? "—— —— ——" : code)
                    .type(T.F.codeBig)
                    .tracking(6)
                    .monospacedDigit()
                    .foregroundStyle(code.isEmpty ? T.C.ink4 : T.C.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(code.isEmpty
                     ? "还没有生成。点下面的按钮算一串。"
                     : "在门锁键盘上输入这串数字")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 10)
                if !code.isEmpty {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let remain = secondsToExpiry(at: ctx.date)
                        Text("本窗口还剩 \(remain / 60):\(String(format: "%02d", remain % 60))")
                            .type(T.F.caption)
                            .foregroundStyle(remain < 120 ? T.C.danger : T.C.ink3)
                    }
                    .padding(.top, 4)
                }
                Spacer().frame(height: 12)
            }
            .padding(24)
        }
    }

    private var enableCard: some View {
        GlassSurface(radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GlyphTile(symbol: "clock.arrow.circlepath", kind: .brass, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("门锁还没开启动态密码")
                            .type(T.F.body)
                            .fontWeight(.medium)
                            .foregroundStyle(T.C.ink)
                        Text("开启后，锁会按周期认这串数字。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                    }
                }
                PrimaryButton(title: "开启动态密码", busy: busy) {
                    Task { await toggle(true) }
                }
            }
        }
    }

    // MARK: - 生成

    private func generate() {
        guard !busy, let kc else { return }
        if let blocked = blockedReason {
            errorLine = blocked
            return
        }
        guard let idx = nextIndex else { return }
        let win = ZOTP.nextWindow()
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodMin: period, idx: idx)
        guard !pwd.isEmpty else {
            // MAC 不是整 6 字节十六进制 ⇒ 算出来的是一串注定开不了锁的数字。
            // 这里宁可什么都不给，也不给一串"看着对"的。
            errorLine = "这把锁的 MAC 不是整 6 字节十六进制，已中止生成。"
            return
        }
        DB.saveOtpIdx(app.currentMac, OtpIdx(idx: idx, invalidTime: win))
        code = pwd
        window = win
        errorLine = nil
        Clip.set(pwd)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func toggle(_ on: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        errorLine = nil
        let result = await app.setZotp(on)
        switch result {
        case .success:
            enabled = on
            DB.saveOtpStatus(app.currentMac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
            if !on {
                code = ""
                window = ""
            }
        case .failure(let error):
            errorLine = error.localizedDescription
        }
    }
}
