// BatteryProfileHomeScreen.swift —— 电池档案（V8 设计语言）
//
// 与 BatteryProfileScreen 的能力对齐：当前电量 + 五档、采样走势、电池档案（型号/换电日期）、低电提醒阈值。
// 修掉一处真 bug：原页提供 25% 档，而引擎 CareSchedule.battThreshold 只接受 10/15/20 —— 选 25 会静默回落 15。
// 这里只保留引擎真的接受的三个档。
import SwiftUI

struct BatteryProfileHomeScreen: View {
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

    private var judgement: String {
        guard app.lock != nil else { return "还没有门锁" }
        if pct < 0 { return "还没采样" }
        return BatteryCare.faceText(pct) + " · 五档 " + tier.label
    }

    var body: some View {
        VPage(title: "电池档案", lead: "采样只在本机，不上传；低电提醒由本机通知排程。") {
            EmptyView()
        } content: {
            if app.lock == nil {
                VEmpty(
                    title: "还没有门锁",
                    reason: "电池档案要挂在具体一把锁上。先到「添加门锁」配对。",
                    actionTitle: "添加门锁"
                ) { }
            } else {
                readingCard
                trendCard
                profileCard
                alertCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var tierColor: Color {
        switch tier {
        case .empty: return V8.C.danger
        case .low: return V8.C.warn
        case .mid: return V8.C.ink2
        case .high, .full: return V8.C.ok
        }
    }

    private var readingCard: some View {
        VCard2 {
            VCardHead(eyebrow: "当前电量", statement: judgement)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "最近采样", tagTint: V8.C.ink4, title: sampleTimeText, value: "")
                VDotRule()
                VDataRow(tag: "采样点数", tagTint: V8.C.ink4, title: "\(samples.count)", value: "个")
            }
            .padding(.top, V8.S.gapS)
            Text("每次读锁状态自动追加一条，保留 90 天。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sampleTimeText: String {
        guard let last = samples.last else { return "尚未采样" }
        return TimeFormat.ago(last.t)
    }

    private var trendCard: some View {
        VCard2 {
            VCardHead(eyebrow: "电量走势", statement: samples.count >= 2 ? "\(samples.count) 个采样点" : "还不够画线")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if samples.count >= 2 {
                VSpark(values: samples.suffix(24).map { Double($0.pct) }, tint: V8.C.okFill, cursor: nil, axis: .samples)
                    .padding(.top, V8.S.gapM)
                Text(trendCaption)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("还没有足够的采样点 —— 每次连接读一次状态，攒到 2 个点就能画出真实走势（不插值、不画假线）。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trendCaption: String {
        let values = samples.map(\.pct)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let days = max(Int(((samples.last?.t ?? 0) - (samples.first?.t ?? 0)) / 86_400_000) + 1, 1)
        return "最近 \(samples.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"
    }

    private var profileCard: some View {
        VCard2 {
            VCardHead(eyebrow: "电池档案", statement: batteryModel.isEmpty ? "未填型号" : batteryModel)
            VDivider2()
                .padding(.top, V8.S.gapM)
            TextField("电池型号（如 CR123A × 2）", text: $batteryModel)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
            Toggle(isOn: $hasChangedAt) {
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("记录换电日期")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                    Text("换电池后回来更新，续航估算才有基准。")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                }
            }
            .frame(minHeight: V8.H.min)
            .padding(.top, V8.S.gapS)
            if hasChangedAt {
                DatePicker("换电日期", selection: $changedAt, displayedComponents: .date)
                    .font(V8.T.body)
                    .frame(minHeight: V8.H.min)
            }
            Button { save() } label: {
                Text("保存电池档案")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, V8.S.gapM)
            if let outcome {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("已") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
            }
        }
    }

    private var alertCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "低电提醒", statement: "阈值 \(threshold)%")
            VDivider2()
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                ForEach([10, 15, 20], id: \.self) { value in
                    thresholdChip(value)
                }
            }
            .padding(.top, V8.S.gapM)
            Text("低于该电量时，本机发一条低电通知（每档只发一次，回电后重置）。五档口径：0–10 空 / 11–20 低 / 21–35 低 / 36–60 中 / 61–80 高 / 81–100 满。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func thresholdChip(_ value: Int) -> some View {
        let selected = threshold == value
        return Button {
            threshold = value
            DB.store.set("kf_batt_threshold", value)
        } label: {
            Text("\(value)%")
                .font(V8.T.tab)
                .foregroundStyle(selected ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(selected ? V8.C.okFill : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("低电阈值 \(value)%")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
