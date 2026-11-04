// SafeModeHomeScreen.swift —— 安全模式（V8 设计语言）
//
// 与 SafeModeScreen 的能力对齐：讲清 A 单验 / B 双验差别；现场切换（cmd20）并**回读确认**；
// C 模式（广播+验证）只说明不切换。降低安全等级（B→A）要二次确认。
import SwiftUI

struct SafeModeHomeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var status: LockStatus?
    @State private var busy = false
    @State private var outcome: String?
    @State private var confirmRelax = false

    private var mac: String { app.lock?.id ?? "" }
    private var isB: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) != 0 }
    private var isC: Bool { (status?.verifyMode ?? 0) == 1 && (status?.broadcastMode ?? 0) == 0 }

    private var modeText: String {
        guard status != nil else { return "未读取" }
        if isB { return "B · 双验" }
        if isC { return "C · 广播+验证" }
        return "A · 单验"
    }

    private var judgement: String {
        if app.lock == nil { return "还没有门锁" }
        if status == nil { return "还没读到锁端模式" }
        return "当前 " + modeText
    }

    var body: some View {
        VPage(title: judgement, lead: "A / B 决定这道锁验一次还是两次。切换后必须回读确认。") {
            EmptyView()
        } content: {
            aCard
            bCard
            currentCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(force: false) }
        .v8Confirm(
            isPresented: $confirmRelax,
            title: "改回 A 模式（单验）？",
            consequence: "锁端将只需单一方式验证就能开锁：原来要两种组合，改回后一种即可。这是降低安全等级，请确认确实需要。",
            confirmTitle: "改回 A 模式",
            isDestructive: true
        ) {
            Task { await setMode(false) }
        }
    }

    private var aCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "A 模式（单验）", statement: "日常最快")
            Text("只需要一种方式验证通过就能开锁：密码、指纹或手机钥匙任一。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "B 模式（双验）", statement: "更安全，多一步")
            Text("需要两种不同方式组合验证：指纹+密码 / 指纹+手机 / 手机+密码。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("注意：只有 A 模式下动态密码才有效。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.danger)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当前模式", statement: modeText)
            VDivider2()
                .padding(.top, V8.S.gapM)
            if isC {
                Text("当前是 C 模式（广播+验证）。本页只在 A / B 两档之间切换。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isB {
                VNavRow(title: "改回 A 模式（单验，更宽松）", detail: "会降低安全等级，需二次确认") {
                    confirmRelax = true
                }
                .padding(.top, V8.S.gapM)
            } else {
                Button { Task { await setMode(true) } } label: {
                    Text(busy ? "切换中…" : "切换到 B 模式（双验，更严）")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .disabled(busy || status == nil)
                .opacity((busy || status == nil) ? 0.45 : 1)
                .padding(.top, V8.S.gapM)
            }
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status == nil {
                VNavRow(title: "重新读取锁状态", detail: "读一次 verifyMode / broadcastMode") {
                    Task { await load(force: true) }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func load(force: Bool) async {
        guard !mac.isEmpty, !busy else { return }
        if status != nil && !force { return }
        busy = true
        defer { busy = false }
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            status = st
            DB.writeStatus(mac, st)
        } catch {
            outcome = "读取失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setMode(_ double: Bool) async {
        let mac = self.mac
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
            await app.refreshStatus()
            let ok = double ? (st.verifyMode == 1 && st.broadcastMode != 0) : (st.verifyMode == 0)
            outcome = ok
                ? (double ? "已切到 B 模式（双验），回读确认" : "已切回 A 模式（单验），回读确认")
                : "命令已下发，但回读显示未生效 —— 请重读后再试"
        } catch {
            outcome = "切换失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
