// SyncTimeScreen.swift —— 校时（门 · 校时）
//
// 这屏干什么：把「锁内时间 / 手机时间 / 偏差」三个数摊开，偏差 > 2 秒才值得写一次；
// 下发 cmd0E 之后回读复核，偏差没归零就说没归零，不写"成功"。
// 数据从哪来：锁端 cmd03 的 lockTime（AppModel.lock 不含锁钟，本页单独读）。
// 主动作：「同步到锁内」——本屏唯一的 signal 填充。
import SwiftUI

struct SyncTimeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 锁钟（协议秒，毫秒 epoch）。nil = 没读到 —— 不拿 0 冒充读数。
    @State private var lockAt: Int64?
    @State private var busy = false
    @State private var result: SyncOutcome?
    @State private var lastSyncedAt: Int64?

    private struct SyncOutcome: Equatable {
        let ok: Bool
        let text: String
    }

    /// 自动校时阈值：偏差超过它才写（与 device.info.autosync 同一口径）。
    private static let driftThreshold = 2

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if app.lock == nil {
                    noLockPanel
                } else {
                    driftPanel
                    actionPanel
                    whyPanel
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("校时")
        .navigationBarTitleDisplayMode(.inline)
        .task { await read() }
        .sensoryFeedback(.success, trigger: result?.ok) { _, new in new == true }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("校时")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    // 状态行最多两行：宁可换行，不要截断或缩字（缩字会把 13pt 压到 10pt，低于可读下限）
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, V.S.pageGutter)
    }

    private var drift: Int? {
        guard let lockAt else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return Int((now - lockAt) / 1000)
    }

    private var headerTone: Tone {
        guard app.lock != nil else { return .neutral }
        guard let drift else { return .attention }
        return abs(drift) <= Self.driftThreshold ? .ok : .attention
    }

    private var headerWord: String {
        guard app.lock != nil else { return "无锁" }
        guard let drift else { return "未读到锁钟" }
        return abs(drift) <= Self.driftThreshold ? "一致" : "有偏差"
    }

    private var headerText: String {
        guard let lock = app.lock else { return "还没有门锁可以校" }
        return "\(lock.name) · 锁钟是所有有效期窗口的判据"
    }

    // MARK: 主角：三个数并排摊开（偏差是本屏的游标）

    private var driftPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "时间对照", trailing: "cmd03 / cmd0E")
                VReadingGrid(items: [
                    .init(label: "锁内时间", value: lockAt.map { TimeFormat.clock($0) } ?? "—"),
                    .init(label: "手机时间",
                          value: TimeFormat.clock(Int64(Date().timeIntervalSince1970 * 1000))),
                    .init(label: "偏差",
                          value: drift.map { $0 == 0 ? "0" : (($0 > 0 ? "+" : "") + "\($0)") } ?? "—",
                          unit: drift == nil ? nil : "秒",
                          tint: driftTint),
                ], columns: 3)
                .padding(.top, V.S.gapXS)

                hairline

                Text(driftNote)
                    .font(V.F.footnote)
                    .foregroundStyle(drift == nil ? V.C.text2 : driftTint)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastSyncedAt {
                    hairline
                    VFieldRow(label: "上次校时", value: TimeFormat.ago(lastSyncedAt), mono: false)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private var driftTint: Color {
        guard let drift else { return V.C.text3 }
        return abs(drift) <= Self.driftThreshold ? V.C.text1 : V.C.warning
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

    // MARK: 主动作

    private var actionPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "下发", trailing: "cmd0E")
                if busy {
                    VBusyRow(text: "正在把手机时间写进锁…")
                } else {
                    VActionButton(title: "同步到锁内", systemImage: "clock.arrow.circlepath", busy: false) {
                        Task { await sync() }
                    }
                }
                if let result {
                    VStatusLine(tone: result.ok ? .ok : .critical, text: result.text)
                }
                hairline
                VOutlineButton(title: "重新读取", systemImage: "arrow.clockwise") {
                    Task { await read() }
                }
                Text("写入的是手机当前时间，不做偏差补偿 —— 所以先确认手机自己的时间是准的。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 为什么这件事重要（把后果写清，不写空洞说明）

    private var whyPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "锁钟偏了会怎样")
                whyLine("临时码有「有效期窗口」，锁钟偏了，码在窗口外就整段打不开。")
                whyLine("开锁命令本身带有效期，锁钟偏太多会回 rc=3「命令已过期」—— 此时只有校时能救。")
                whyLine("每次读状态时本机都会算一次偏差，超过 2 秒才写；所以这一页平时只是看一眼。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func whyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: V.S.gapS) {
            VStateDot(tone: .neutral, word: "须知")
            Text(text)
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 空态（给下一步出路）

    private var noLockPanel: some View {
        VCard {
            VEmptyState(
                title: "还没有门锁可以校",
                message: "校时是写给锁内时钟的，得先有一把锁。先添加门锁，再回这一页对时。",
                actionTitle: "添加门锁",
                systemImage: "clock.arrow.circlepath"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 读写

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
        busy = true
        result = nil
        // 真链路：ensureConnected → cmd0E → 回读 cmd03 复核偏差（AppModel 已封装）。
        let r = await app.syncTime()
        busy = false
        switch r {
        case .failure(let e):
            let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            result = SyncOutcome(ok: false, text: "同步失败：\(msg)")
        case .success(let pair):
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            lockAt = Int64((ZKProtocol.protoSecondsToUnix(Int64(pair.1)) * 1000).rounded())
            lastSyncedAt = now
            SettingsStore.shared.lockClockSyncedAt = now
            let residual = Int((Int64(Date().timeIntervalSince1970 * 1000) - (lockAt ?? now)) / 1000)
            result = SyncOutcome(ok: abs(residual) <= Self.driftThreshold,
                                 text: "同步完成 · 回读偏差 \(residual) 秒")
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(V.C.hairline)
            .frame(height: V.S.hair)
    }
}