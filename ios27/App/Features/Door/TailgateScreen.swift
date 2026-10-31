// TailgateScreen.swift —— 防尾随 / 自动上锁（cmd24）。
//
// 来源：原 App/UI/SettingsSubPages.swift 的 TailgateView（防尾随入室页）。
// 这屏干什么：选 2–6 秒档并下发 cmd24；锁在电控开锁后等待该时长自动上锁，防止尾随。
// 数据从哪来：DB.tailgate(mac) 的已存档位；写入成功后落同一键。
// 主动作：唯一的「设置」按钮（真下发，失败如实说）。
import SwiftUI

struct TailgateScreen: View {
    @Environment(AppModel.self) private var app
    @State private var seconds = 6
    @State private var loaded = false
    @State private var busy = false
    @State private var outcome: String?

    private var mac: String { app.lock?.id ?? "" }
    private var supported: Bool {
        guard let kc = app.currentKeychain else { return false }
        return PidMap.canTailgate(kc.pid, fw: kc.fw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        VCardHeader(title: "自动上锁等待时长")
                        Text("门锁用蓝牙钥匙、密码、指纹等电控方式开锁后，等待这段时间会自动上锁。档位 2–6 秒，默认 6 秒。")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: V.S.gapS) {
                            ForEach(2 ... 6, id: \.self) { value in
                                Button {
                                    seconds = value
                                } label: {
                                    VTag(text: "\(value) 秒", tint: seconds == value ? V.C.blue : V.C.text3, filled: seconds == value)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(seconds == value ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                        .padding(.top, V.S.gapS)
                        VRowDivider()
                        VValueRow(label: "当前档位", value: "\(seconds) 秒")
                        VActionButton(title: busy ? "正在下发…" : "设置", systemImage: "timer") {
                            Task { await save() }
                        }
                        .disabled(busy || !supported)
                        .opacity(supported ? 1 : 0.45)
                        if let outcome {
                            Text(outcome).font(V.F.footnote)
                                .foregroundStyle(outcome.hasPrefix("设置成功") ? V.C.rewardGreen : V.C.pink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !supported {
                            Text("这把锁的型号或固件不支持防尾随（V1 Pro 需固件 1.0.3 以上）。")
                                .font(V.F.footnote).foregroundStyle(V.C.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
                VCard(style: .warm) {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        VCardHeader(title: "为什么不是越长越好", showsChevron: false)
                        Text("等待时间就是尾随者能挤进门的那几秒。家里有老人小孩可以取 5–6 秒；独居或楼道常有陌生人时取 2–3 秒更稳。")
                            .font(V.F.body)
                            .foregroundStyle(V.C.text9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("防尾随")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("防尾随")
                .font(V.F.displayA)
                .foregroundStyle(V.C.text1)
            Text(app.lock.map { "\($0.name) · \($0.model)" } ?? "还没有门锁")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private func load() {
        guard !loaded, !mac.isEmpty else { return }
        loaded = true
        if let c = DB.tailgate(mac), (2 ... 6).contains(c.interval) { seconds = c.interval }
    }

    private func save() async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setAutoLock(seconds)
            DB.saveTailgate(mac, TailgateCfg(interval: seconds, at: Date().timeIntervalSince1970 * 1000))
            outcome = "设置成功：开锁后 \(seconds) 秒自动上锁"
        } catch {
            outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("TailgateScreen") {
    NavigationStack { TailgateScreen() }
        .environment(AppModel())
        .environment(Router())
}
