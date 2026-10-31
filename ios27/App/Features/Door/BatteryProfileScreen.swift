// BatteryProfileScreen.swift —— 电池档案（电量采样 / 五档 / 低电提醒 / 型号与换电日期）。
//
// 来源：原 App/Core/BatteryCare.swift（五档/采样/低电通知）+ App/UI/DeviceInfoView.swift 的「电池档案」段。
// 这屏干什么：把电量从「一个百分比」摊成可核对的采样走势、五档读数与档案（型号/换电日期），
//   并允许改低电提醒阈值 —— 低电通知由 BatteryCare 在每次读 03 时自动判定并排程。
// 数据从哪来：BatteryCare.samples / BatteryCare.tier / LockArchive.meta。
// 主动作：「保存电池档案」。
import SwiftUI

struct BatteryProfileScreen: View {
    @Environment(AppModel.self) private var app
    @State private var batteryModel = ""
    @State private var changedAt = Date()
    @State private var hasChangedAt = false
    @State private var threshold = 15
    @State private var loaded = false
    @State private var outcome: String?

    private var mac: String { app.lock?.id ?? "" }
    private var samples: [BattSample] { BatteryCare.samples(mac) }
    private var pct: Int { BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1) }
    private var tier: BatteryCare.Tier { BatteryCare.tier(pct) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if app.lock == nil {
                    noLockCard
                } else {
                    readingCard
                    trendCard
                    profileCard
                    alertCard
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("电池档案")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("电池档案")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("采样只在本机，不上传；低电提醒由本机通知排程。")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
        .padding(.horizontal, V.S.pageGutterA)
    }

    private var noLockCard: some View {
        VCard {
            Text("还没有门锁 —— 电池档案要挂在具体一把锁上。先到「添加门锁」配对。")
                .font(V.F.body).foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var readingCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "当前电量")
                HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                    Image(systemName: tier.icon)
                        .font(V.F.displayE)
                        .foregroundStyle(tierColor)
                        .accessibilityHidden(true)
                    Text(BatteryCare.faceText(pct))
                        .font(V.F.displayA)
                        .foregroundStyle(V.C.text1)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    VTag(text: "五档 · " + tier.label, tint: tierColor, filled: false)
                }
                VRowDivider()
                VValueRow(label: "最近采样", value: sampleTimeText)
                VRowDivider()
                VValueRow(label: "采样点数", value: "\(samples.count) 个", note: "每次读锁状态（cmd03）自动追加一条，保留 90 天。")
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var trendCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "电量走势")
                if samples.count >= 2 {
                    VMiniBars(values: samples.suffix(24).map { Double($0.pct) }, tint: V.C.rewardGreen)
                    Text(trendCaption)
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("还没有足够的采样点 —— 每次连接读一次状态，攒到 2 个点就能画出真实走势（不插值、不画假线）。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var trendCaption: String {
        let values = samples.map(\.pct)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let days = max(Int(((samples.last?.t ?? 0) - (samples.first?.t ?? 0)) / 86_400_000) + 1, 1)
        return "最近 \(samples.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"
    }

    private var profileCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "电池档案")
                VTextFieldRow(label: "电池型号", text: $batteryModel, placeholder: "如 CR123A × 2")
                VToggleRow(title: "记录换电日期", detail: "换电池后回来更新，续航估算才有基准。", isOn: $hasChangedAt)
                if hasChangedAt {
                    DatePicker("换电日期", selection: $changedAt, displayedComponents: .date)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                }
                VActionButton(title: "保存电池档案", systemImage: "checkmark") { save() }
                if let outcome {
                    Text(outcome).font(V.F.footnote)
                        .foregroundStyle(outcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var alertCard: some View {
        VCard(style: .warm) {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "低电提醒")
                VValueRow(label: "提醒阈值", value: "\(threshold)%", note: "低于该电量时，本机发一条低电通知（每档只发一次，回电后重置）。")
                HStack(spacing: V.S.gapS) {
                    ForEach([10, 15, 20, 25], id: \.self) { value in
                        Button { threshold = value; DB.store.set("kf_batt_threshold", value) } label: {
                            VTag(text: "\(value)%", tint: threshold == value ? V.C.rewardGreen : V.C.text3, filled: threshold == value)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("五档口径：0–10 空 / 11–20 低 / 21–35 低 / 36–60 中 / 61–80 高 / 81–100 满。低于 20% 时界面自动进入省电视觉档。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private var tierColor: Color {
        switch tier.tone {
        case .ok: return V.C.rewardGreen
        case .warn: return V.C.coral
        case .danger: return V.C.red
        case .accent: return V.C.blue
        case .neutral: return V.C.text3
        }
    }

    private var sampleTimeText: String {
        guard let latest = BatteryCare.latest(mac) else { return "尚未采样" }
        return LockStats.sampleTimeText(latest.t)
    }

    private func load() {
        guard !loaded, !mac.isEmpty else { return }
        loaded = true
        let m = LockArchive.meta(mac)
        batteryModel = m.batteryModel
        hasChangedAt = m.batteryChangedAt > 0
        if m.batteryChangedAt > 0 { changedAt = Date(timeIntervalSince1970: m.batteryChangedAt) }
        threshold = CareSchedule.battThreshold
    }

    private func save() {
        guard !mac.isEmpty else { return }
        var m = LockArchive.meta(mac)
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = hasChangedAt ? changedAt.timeIntervalSince1970 : 0
        LockArchive.save(mac, m)
        outcome = "已保存电池档案"
    }
}

#Preview("BatteryProfileScreen") {
    NavigationStack { BatteryProfileScreen() }
        .environment(AppModel())
        .environment(Router())
}
