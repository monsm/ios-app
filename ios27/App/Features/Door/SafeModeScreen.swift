// SafeModeScreen.swift —— 安全模式说明与切换（cmd20）。
//
// 来源：原 App/UI/SettingsSubPages.swift 的 SafemodeIntroView（A/B 模式说明页）。
// 这屏干什么：讲清 A 模式单验 / B 模式双验的差别，并可现场切换；切换后必须回读 verifyMode 确认。
// 数据从哪来：LockService.getStatus 的 verifyMode / broadcastMode（进页读一次）。
// 主动作：「切换到 B 模式」或「改回 A 模式」—— 同屏只出现一枚。
import SwiftUI

struct SafeModeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var status: LockStatus?
    @State private var busy = false
    @State private var outcome: String?
    @State private var confirmRelax = false

    private var mac: String { app.lock?.id ?? "" }
    private var isB: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) != 0 }
    private var isC: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) == 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        VCardHeader(title: "A 模式（单验）")
                        Text("只需要一种方式验证通过就能开锁：密码、指纹或手机钥匙任一。日常最快。")
                            .font(V.F.body).foregroundStyle(V.C.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
                VCard(style: .warm) {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        VCardHeader(title: "B 模式（双验）")
                        Text("需要两种不同方式组合验证：指纹+密码 / 指纹+手机 / 手机+密码。更安全，但每次开门要多一步。")
                            .font(V.F.body).foregroundStyle(V.C.text9)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("注意：只有 A 模式下临时开锁密码（ZOTP）才有效。")
                            .font(V.F.footnote).foregroundStyle(V.C.pink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
                VCard {
                    VStack(alignment: .leading, spacing: V.S.gapS) {
                        VCardHeader(title: "当前模式")
                        VValueRow(label: "锁端状态", value: modeText)
                        if isC {
                            Text("当前是 C 模式（广播+验证）。本页只在 A / B 两档之间切换。")
                                .font(V.F.footnote).foregroundStyle(V.C.text3)
                        } else if isB {
                            VOutlineButton(title: "改回 A 模式（单验，更宽松）", systemImage: "lock.open", tint: V.C.coral) {
                                confirmRelax = true
                            }
                            .disabled(busy)
                        } else {
                            VActionButton(title: busy ? "切换中…" : "切换到 B 模式（双验，更严）", systemImage: "lock.rotation") {
                                Task { await setMode(true) }
                            }
                            .disabled(busy || status == nil)
                        }
                        if let outcome {
                            Text(outcome).font(V.F.footnote)
                                .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if status == nil {
                            VOutlineButton(title: "读取锁状态", systemImage: "arrow.clockwise") {
                                Task { await load(force: true) }
                            }
                            .disabled(busy)
                        }
                    }
                }
                .padding(.horizontal, V.S.cardGutter)
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("安全模式")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(force: false) }
        .confirmationDialog("改回 A 模式（单验）？", isPresented: $confirmRelax, titleVisibility: .visible) {
            Button("改回 A 模式", role: .destructive) { Task { await setMode(false) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("锁端将只需单一方式验证就能开锁：原来要两种组合，改回后一种即可。这是降低安全等级，请确认确实需要。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("安全模式")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("A / B 决定这道锁验一次还是两次")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var modeText: String {
        guard let st = status else { return "未读取" }
        if isB { return "B · 双验" }
        if isC { return "C · 广播+验证" }
        return "A · 单验"
    }

    private func load(force: Bool) async {
        guard !mac.isEmpty, !busy else { return }
        guard force || status == nil else { return }
        busy = true
        defer { busy = false }
        do {
            status = try await LockService.shared.getStatus(mac: mac)
        } catch {
            outcome = "读取失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setMode(_ double: Bool) async {
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setValidationMode(double)
            let st = try await LockService.shared.getStatus(mac: mac)
            status = st
            DB.writeStatus(mac, st)
            let ok = double ? (st.verifyMode == 1 && st.broadcastMode != 0) : (st.verifyMode == 0)
            outcome = ok ? (double ? "已切到 B 模式（双验），回读确认" : "已切回 A 模式（单验），回读确认") : "命令已下发，但回读显示未生效 —— 请重读后再试"
        } catch {
            outcome = "切换失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("SafeModeScreen") {
    NavigationStack { SafeModeScreen() }
        .environment(AppModel())
        .environment(Router())
}
