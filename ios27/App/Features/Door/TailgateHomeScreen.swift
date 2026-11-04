// TailgateHomeScreen.swift —— 防尾随 / 自动上锁（V8 设计语言）
//
// 与 TailgateScreen 的能力对齐：选 2–6 秒档并下发 cmd24；型号/固件门禁；失败如实说。
import SwiftUI

struct TailgateHomeScreen: View {
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

    private var judgement: String {
        if app.lock == nil { return "还没有门锁" }
        if !supported { return "这把锁不支持防尾随" }
        return "开锁后 \(seconds) 秒自动上锁"
    }

    var body: some View {
        VPage(title: "防尾随", lead: app.lock.map { "\($0.name) · \($0.model)" } ?? "还没有门锁") {
            EmptyView()
        } content: {
            settingCard
            whyCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var settingCard: some View {
        VCard2 {
            VCardHead(eyebrow: "自动上锁等待时长", statement: judgement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("门锁用蓝牙钥匙、密码、指纹等电控方式开锁后，等待这段时间会自动上锁。档位 2–6 秒，默认 6 秒。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: V8.S.gapChip) {
                    ForEach(2 ... 6, id: \.self) { value in
                        secondChip(value)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VDataRow(tag: "当前档位", tagTint: V8.C.ink4, title: "\(seconds)", value: "秒")
            Button {
                Task { await save() }
            } label: {
                Text(busy ? "正在下发…" : "设置")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(busy || !supported)
            .opacity(supported ? 1 : 0.45)
            .padding(.top, V8.S.gapM)
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("设置成功") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !supported {
                Text("这把锁的型号或固件不支持防尾随（V1 Pro 需固件 1.0.3 以上）。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func secondChip(_ value: Int) -> some View {
        let selected = seconds == value
        return Button {
            seconds = value
        } label: {
            Text("\(value) 秒")
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) 秒")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var whyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "为什么不是越长越好", statement: "等待时间就是尾随者能挤进门的那几秒")
            Text("家里有老人小孩可以取 5–6 秒；独居或楼道常有陌生人时取 2–3 秒更稳。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        guard !loaded, !mac.isEmpty else { return }
        loaded = true
        if let c = DB.tailgate(mac), (2 ... 6).contains(c.interval) { seconds = c.interval }
    }

    private func save() async {
        let mac = self.mac
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
