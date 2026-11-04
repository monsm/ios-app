// SyncTimeHomeScreen.swift —— 校准门锁时间（V8 设计语言）
//
// 与 SyncTimeScreen 的能力对齐：锁内时间 / 手机时间 / 偏差三数并排；偏差 > 2 秒才写；
// 下发 cmd0E 后回读复核，偏差没归零就说没归零。锁钟偏了会怎样：三条须知。
import SwiftUI

struct SyncTimeHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var lockAt: Int64?
    @State private var busy = false
    @State private var result: SyncOutcome?
    @State private var lastSyncedAt: Int64?

    private struct SyncOutcome: Equatable {
        let ok: Bool
        let text: String
    }

    private static let driftThreshold = 2

    private var drift: Int? {
        guard let lockAt else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return Int((now - lockAt) / 1000)
    }

    private var judgement: String {
        guard app.lock != nil else { return "还没有门锁可以校" }
        guard let drift else { return "还没读到锁钟" }
        return abs(drift) <= Self.driftThreshold ? "锁钟与手机一致" : "锁钟偏了 \(drift) 秒"
    }

    private var lead: String {
        guard let lock = app.lock else {
            return "校时是写给锁内时钟的，得先有一把锁。先添加门锁，再回这一页对时。"
        }
        return "\(lock.name) · 锁钟是所有有效期窗口的判据。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if app.lock == nil {
                VEmpty(
                    title: "还没有门锁可以校",
                    reason: "校时是写给锁内时钟的，得先有一把锁。先添加门锁，再回这一页对时。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                driftCard
                actionCard
                whyCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await read() }
        .sensoryFeedback(.success, trigger: result?.ok) { _, new in new == true }
    }

    private var driftTint: Color {
        guard let drift else { return V8.C.ink3 }
        return abs(drift) <= Self.driftThreshold ? V8.C.ink1 : V8.C.warn
    }

    private var driftNote: String {
        guard let drift else {
            return "还没读到锁钟。走近门锁、确认蓝牙开着，再点下面的「重新读取」。"
        }
        if abs(drift) <= Self.driftThreshold {
            return "偏差在 \(Self.driftThreshold) 秒以内，不用写。临时码与时间窗凭证此刻是有效的。"
        }
        return "偏差已经超过 \(Self.driftThreshold) 秒。锁内时间偏了，临时码与时间窗凭证会整段失效 —— 现在同步一次。"
    }

    private var driftCard: some View {
        VCard2 {
            VCardHead(eyebrow: "时间对照", statement: judgement, trailing: "本机 / 锁端")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "锁内时间", value: lockAt.map { TimeDisplay.clock($0) } ?? "—"),
                .init(label: "手机时间", value: TimeDisplay.clock(Int64(Date().timeIntervalSince1970 * 1000)))
            ])
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.vertical, V8.S.gapM)
            VDataRow(tag: "偏差", tagTint: driftTint, title: drift.map { $0 == 0 ? "0" : (($0 > 0 ? "+" : "") + "\($0)") } ?? "—", value: "", unit: drift == nil ? nil : "秒")
            Text(driftNote)
                .font(V8.T.footnote)
                .foregroundStyle(drift == nil ? V8.C.ink3 : driftTint)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if let lastSyncedAt {
                VDivider2()
                    .padding(.vertical, V8.S.gapM)
                VDataRow(tag: "上次校时", tagTint: V8.C.ink4, title: TimeFormat.ago(lastSyncedAt), value: "")
            }
        }
    }

    private var actionCard: some View {
        VCard2 {
            VCardHead(eyebrow: "下发", statement: "立即生效")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if busy {
                VBusy(text: "正在把手机时间写进锁…")
            } else {
                Button { Task { await sync() } } label: {
                    Text("同步到锁内")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
            }
            if let result {
                Text(result.text)
                    .font(V8.T.footnote)
                    .foregroundStyle(result.ok ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VNavRow(title: "重新读取", detail: "读锁内时间再算一次偏差") {
                Task { await read() }
            }
            .padding(.top, V8.S.gapS)
            Text("写入的是手机当前时间，不做偏差补偿 —— 所以先确认手机自己的时间是准的。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "锁钟偏了会怎样", statement: "三条须知")
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                Text("· 临时码有「有效期窗口」，锁钟偏了，码在窗口外就整段打不开。")
                Text("· 开锁命令自带有效期，锁钟偏得太多会被判「命令已过期」—— 这种情况只有校时能救。")
                Text("· 每次读状态时本机都会算一次偏差，超过 2 秒才写；所以这一页平时只是看一眼。")
            }
            .font(V8.T.footnote)
            .foregroundStyle(V8.C.ink3)
            .padding(.top, V8.S.gapM)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func read() async {
        guard app.lock != nil, !busy else { return }
        busy = true
        defer { busy = false }
        await app.refreshStatus()
        if let t = app.lastStatus?.status.lockTime, t > 0 {
            lockAt = Int64((ZKProtocol.protoSecondsToUnix(Int64(t)) * 1000).rounded())
        } else {
            lockAt = nil
        }
        result = nil
    }

    @MainActor
    private func sync() async {
        guard !busy, app.lock != nil else { return }
        let mac = app.currentMac
        busy = true
        result = nil
        let r = await app.syncTime()
        busy = false
        switch r {
        case .failure(let e):
            let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            result = SyncOutcome(ok: false, text: "同步失败：\(msg)")
        case .success(let pair):
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let drift = pair.1
            lockAt = now + Int64(drift) * 1000
            lastSyncedAt = now
            DB.saveSyncTime(mac, Double(now))
            let residual = -drift
            result = SyncOutcome(ok: abs(residual) <= Self.driftThreshold,
                                 text: "同步完成 · 回读偏差 \(residual) 秒")
        }
    }
}
