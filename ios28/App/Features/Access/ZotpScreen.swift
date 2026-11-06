// ZotpScreen.swift —— 锁端动态密码。这是一个纯离线计算：skey + MAC + 时间窗口。
import SwiftUI

@MainActor
struct ZotpScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var enabled = false
    @State private var errorLine: String?
    @State private var copied = false

    private var kc: Keychain? { DB.keychainForUnlock(app.currentMac) }
    private var period: Int { DB.readStatus(app.currentMac)?.zotpPeriod ?? 30 }
    private var idx: Int { DB.otpIdx(app.currentMac)?.idx ?? 0 }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 动态密码", back: { dismiss() })

            DisplayLine(text: enabled ? "此刻的\n一串数字。" : "让门锁\n自己报数。", size: 36)
                .padding(.top, 16)
            Text("动态密码由门锁和手机各自算出，不经过网络。每 \(period) 分钟换一次。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            if enabled {
                codeCard
                    .padding(.top, 22)
                ReadingRow(items: [
                    (label: "周期", value: "\(period)", unit: "分钟"),
                    (label: "失效", value: ZOTP.nextWindow(), unit: nil),
                    (label: "索引", value: "\(idx)", unit: nil),
                ])
                .padding(.top, 24)
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

            if enabled {
                GhostButton(title: "复制这串数字", symbol: copied ? "checkmark" : "doc.on.doc") {
                    if let code = currentCode {
                        Clip.set(code)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
                .padding(.top, 18)

                Button {
                    Task { await toggle(false) }
                } label: {
                    Text("关闭动态密码")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            enabled = DB.otpStatus(app.currentMac)?.on ?? false
        }
    }

    private var currentCode: String? {
        guard let kc else { return nil }
        let code = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodMin: period, idx: idx)
        return code.isEmpty ? nil : code
    }

    private var codeCard: some View {
        DaylightPane(height: 250, showSill: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Kicker(text: "DYNAMIC · 前门", dot: true, tint: T.C.ink2)
                    Spacer()
                    Badge(text: "离线计算")
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(currentCode ?? "—— —— ——")
                        .type(T.F.codeBig)
                        .tracking(6)
                        .monospacedDigit()
                        .foregroundStyle(T.C.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text("在门锁键盘上输入这串数字")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 10)
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

    private func toggle(_ on: Bool) async {
        busy = true
        defer { busy = false }
        errorLine = nil
        let result = await app.setZotp(on)
        switch result {
        case .success:
            enabled = on
            DB.saveOtpStatus(app.currentMac, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
        case .failure(let error):
            errorLine = error.localizedDescription
        }
    }
}
