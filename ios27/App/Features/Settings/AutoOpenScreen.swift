// AutoOpenScreen.swift —— 靠近自动开锁（默认关，fail-closed）。
//
// 这屏干什么：主开关「走近自动开门」；开启后才出现面容确认两档、风险说明、距离标定与
// 「上次没自动开的原因」。默认关是有意的 —— 一个会自己开门的 App，默认开就是错的。
// 数据从哪来：SettingsStore.shared（开关 / 确认档 / 标定时刻 / 拒因）+ AppModel.lock（是否已连上）。
// 主动作：唯一 signal 填充是「开始标定 / 重新标定」（开启后才有）；主开关本身走墨色 Toggle。
import SwiftUI

struct AutoOpenScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    private var store: SettingsStore { SettingsStore.shared }

    @State private var calibrating = false

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "靠近自动开锁", tone: tone, status: status)
                mainPanel
                if AutoOpen.on {
                    confirmPanel
                    calibrationPanel
                    rejectPanel
                } else {
                    offPanel
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("靠近自动开锁")
        .navigationBarTitleDisplayMode(.inline)
        .task { syncAutoOpenState() }
    }

    // MARK: 页头
    private var tone: Tone {
        AutoOpen.on ? (app.lock?.isConnected == true ? .ok : .attention) : .neutral
    }

    private var status: String {
        guard AutoOpen.on else { return "关闭 · 走到门前仍需手动点开锁" }
        guard app.lock?.isConnected == true else { return "已开启 · 但锁未连接，自动开锁不会触发" }
        return "已开启 · \(faceTier.title) · 仅前台生效"
    }

    // MARK: 主角：主开关
    private var mainPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "主开关")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingToggle(
                        label: "走近自动开门",
                        note: "默认关。开启后 App 在前台且靠近门时自动下发开锁 —— 这是唯一一个不需要你动手就会开门的功能，所以它默认不生效。",
                        isOn: autoOpenBinding
                    )
                    SettingRule()
                    HStack(spacing: V.S.gapMS) {
                        VStatusLine(tone: AutoOpen.on ? .live : .neutral,
                                   text: AutoOpen.on ? "自动开锁 开" : "自动开锁 关")
                        VStatusLine(tone: app.lock?.isConnected == true ? .ok : .attention,
                                   text: app.lock?.isConnected == true ? "锁已连接" : "锁未连接")
                    }
                    SettingRule()
                    SettingsNote(text: "门控边界：只在 App 在前台时生效；布防时段内、以及防拆事件之后，自动开锁会被自动关掉 —— 这些否决不给你留提示，所以下面会记「上次没自动开的原因」。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 关闭时的说明（不是空态，是"现在是什么样 + 怎么打开"）
    private var offPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                Text("现在走到门前，App 不会替你开门")
                    .font(V.F.bodyStrong)
                    .foregroundStyle(V.C.text1)
                SettingsNote(text: "下一步：如果确实想要「走到门口就开」，把上面的开关打开。打开后建议先做一次距离标定 —— 不标定的话，门内经过也会触发。")
                VOutlineButton(title: "去门页手动开锁", systemImage: "door.left.hand.closed") {
                    // 真交互：切到「门」页 —— 开锁只在那一页的刻度盘上，别处不给开锁入口。
                    router.select(.door)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 面容确认
    private var confirmPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "确认档")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingChips(items: FaceConfirmTier.allCases,
                                 title: { $0.title },
                                 selection: faceTierBinding)
                    SettingsNote(text: faceTier.note)
                    SettingRule()
                    VFieldRow(label: "当前档位", value: faceTier.title, mono: false)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 距离标定
    private var calibrationPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "距离标定")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    VReadingGrid(items: [
                        .init(label: "上次标定",
                              value: calibrationAt.map { TimeFormat.dayShort($0) } ?? "未标定",
                              tint: calibrationAt == nil ? V.C.warning : V.C.text1),
                        .init(label: "触发距离", value: calibrationAt == nil ? "默认（-40 dBm）" : "已校准",
                              tint: V.C.text2),
                    ], columns: 2)
                    .padding(.top, V.S.gapXS)
                    SettingRule()
                    SettingsNote(text: "标定方式：站在门外约一步的位置，点下面的按钮，App 会记下那一刻的信号强度作为门槛。没标定就打开自动开锁，门内走动也可能触发。")
                    if calibrating {
                        VBusyRow(text: "正在采集信号 · 请保持站在门外")
                    } else {
                        VActionButton(title: calibrationAt == nil ? "开始标定" : "重新标定",
                                      systemImage: "dot.radiowaves.left.and.right") {
                            calibrate()
                        }
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 上次没自动开的原因（诚实：没记录就写没记录）
    private var rejectPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "上一次")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    if let reason = lastSkipReason {
                        VStatusLine(tone: .attention, text: reason)
                        SettingRule()
                        SettingsNote(text: "这条是这次没自动开的原因。想看每一次的开锁结果，去台账页。")
                    } else {
                        Text("还没有「没自动开」的记录")
                            .font(V.F.body)
                            .foregroundStyle(V.C.text1)
                        SettingsNote(text: "走到门前没开门时，这里会写清原因（信号太弱 / 在布防时段 / 面容未通过）。现在还没有这样的记录 —— 说明自动开锁还没被否决过。")
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: - 动作

    private func calibrate() {
        guard let mac = app.lock?.id, !calibrating else { return }
        calibrating = true
        Task { @MainActor in
            // 真链路：连上锁后读 5 次当前链路 RSSI，取 P95 作为这把锁的距离门槛。
            try? await LockService.shared.ensureConnected(mac: mac)
            var samples: [Int] = []
            for _ in 0 ..< 5 {
                let r: Int? = await withCheckedContinuation { cont in
                    BLEService.shared.readLinkRSSI(timeoutMs: 1200) { cont.resume(returning: $0) }
                }
                if let r { samples.append(r) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if AutoOpen.saveAutocal(mac, samples: samples) != nil {
                store.calibrationAt = Int64(Date().timeIntervalSince1970 * 1000)
            } else {
                store.calibrationAt = nil
            }
            calibrating = false
        }
    }

    // MARK: - AutoOpen 真值桥接

    private var autoOpenBinding: Binding<Bool> {
        Binding(get: { AutoOpen.on }, set: { store.autoOpenEnabled = $0; AutoOpen.on = $0 })
    }

    private var faceTier: FaceConfirmTier {
        AutoOpen.faceTier == 0 ? .free : .strict
    }

    private var faceTierBinding: Binding<FaceConfirmTier> {
        Binding(get: { faceTier },
                set: { v in
                    store.faceConfirm = v
                    AutoOpen.faceTier = (v == .strict) ? 1 : 0
                })
    }

    private var calibrationAt: Int64? {
        guard let cal = AutoOpen.autocal(app.lock?.id ?? "") else { return nil }
        return Int64(cal.at * 1000)
    }

    private var lastSkipReason: String? {
        AutoOpen.lastReject(app.lock?.id ?? "")?.reason
    }

    private func syncAutoOpenState() {
        store.autoOpenEnabled = AutoOpen.on
        store.faceConfirm = faceTier
        if let cal = AutoOpen.autocal(app.lock?.id ?? "") { store.calibrationAt = Int64(cal.at * 1000) }
        store.lastSkipReason = lastSkipReason
    }
}
