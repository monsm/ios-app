import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 凭证回收站
// ═══════════════════════════════════════════════════════════════════════
//
// 补的是**又一条"界面反复承诺、实际做不到"的链**：
//
//   · 多处文案写着「并入回收站（可整组还原）」「本机回收站 N 天内可找回」
//   · CredentialOrg.undoRemove / undoBin / reclaim 实现完整
//   · 但 undoRemove **零调用** —— 全仓没有任何地方能还原
//
// 于是用户删掉一条凭证，看到"可还原"的提示，点进去却只能"清空"。
//
// ═══ 关于 hard 参数 ═══
// undoRemove 的 hard 表示"锁端那条是不是已经真删了"：
//   · false：撤销还没发出去的删除 + 本机放回原处（可完整恢复）
//   · true ：本机放回原处，但锁端已经真删 —— 密码可重发，指纹只能到锁前重录
//
// 本页用 false：这是"刚删完就后悔"的主路径。若锁端其实已经删了，
// undoRemove 会把它自己的说明文字返回上来，本页**原样展示**那段话，
// 不在界面上替它做美化 —— 它比我能写的更准确。
struct CredentialBinView: View {
    @EnvironmentObject private var app: AppState
    /// 队列真正下发成功时会写 lastReceipt —— 但全仓没有一处读它（第 50 轮扫出来的"有写无读"）。
    /// 而它是这条最长异步链**唯一的结果信号**：早上下令撤销、晚上回家连上锁、下发成功，
    /// 然后什么都没告诉用户。这里把它显出来，闭环才算合上。
    @ObservedObject private var sense = LinkSense.shared

    @State private var entries: [CredBinEntry] = []
    @State private var lastMessage: String?
    /// 还没下发给门锁的撤销/变更命令。
    @State private var pending: [CredQueueItem] = []

    private var mac: String { app.currentMac }

    private var retainDays: Int { CredentialOrg.reclaimDays() }

    var body: some View {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("回收站", style: .inline) {
            if entries.isEmpty {
                XPanel(kind: .group) {
                    XEmptyState(systemImage: "trash.slash",
                                title: "回收站是空的",
                                message: "删除或停用的钥匙会在这里保留 \(retainDays) 天，可以放回原位。")
                }
            } else {
                // 六图改造 (2026-10-24): 顶部图5 读数卡（44px 回收站条目数 + 环）
                binStatsCard
                retentionCard
                if receiptVisible { receiptCard }
                if !pending.isEmpty { pendingCard }
                listCard
            }
            if entries.isEmpty && !pending.isEmpty { pendingOnlyCard }
        }
        .onAppear { reload() }
        .alert("恢复结果", isPresented: Binding(get: { lastMessage != nil },
                                               set: { if !$0 { lastMessage = nil } })) {
            Button("知道了") { lastMessage = nil }
        } message: {
            Text(lastMessage ?? "")
        }
    }

    // ── 保留期说明 ──────────────────────────────────────────
    /// 图 5 读数卡：44px 项在回收站 + 环
    private var binStatsCard: some View {
        let n = entries.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("回收站")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(n),
                            color: n == 0 ? XPalette.textTertiary : XPalette.accentText,
                            unit: "项在回收站")
                        Text(n == 0 ? "空的" : "保留 \(retainDays) 天，可以放回原位")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 68,
                        progress: n == 0 ? 0.02 : min(1, Double(n) / 6),
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
    }

    private var retentionCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("保留期")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
            HStack(spacing: XSpace.s) {
                // 这是回收站，图标就该是垃圾桶。原来用 clock.arrow.circlepath（时钟+回溯），
                // 那是「时间同步 / 保养历史」的语义 —— 同一个图标在两处表示两种完全无关的东西。
                Image(systemName: "trash")
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(XPalette.accentText)
                    .accessibilityHidden(true)
                Text("删除后保留 \(retainDays) 天。期间可以「恢复」放回原位；超过保留期会自动清理。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("删除后保留 \(retainDays) 天，期间可以恢复")
                }
            }

    // ── 条目 ───────────────────────────────────────────────
    private var listCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                    row(e)
                    if idx < entries.count - 1 {
                        XHairline(inset: XSpace.card)
                    }
                }
            }
        }
    }

    private func row(_ e: CredBinEntry) -> some View {
        HStack(spacing: XSpace.m) {
            Image(systemName: e.fp != nil ? "touchid" : "key.fill")
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.textSub)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.text)
                    .xFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text(e.sourceName + " · " + ageText(e.at))
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }
            Spacer(minLength: XSpace.s)
            Button("恢复") { restore(e) }
                .xFont(.footnote, weight: .medium)
                .foregroundStyle(XPalette.accentText)
                .padding(.vertical, XSpace.xs)
                .accessibilityLabel("恢复 " + e.text)
        }
        .padding(XSpace.card)
        .frame(minHeight: XHit.min)
    }

    private func ageText(_ at: Double) -> String {
        // at 是 epoch **秒**（CredBinEntry 注释里有说明；注意与 CachedLog 的毫秒口径不同）
        guard at > 0 else { return "时间未知" }
        let d = Date(timeIntervalSince1970: at)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = WeekCal.gregorian
        f.dateFormat = "M-d HH:mm"
        return f.string(from: d)
    }

    // ── 刚刚发出去的回执 ───────────────────────────────────
    //
    // 只在"最近 5 分钟内刚发生过下发"时出现 —— 不是常驻状态，是一条确认。
    private var receiptVisible: Bool {
        sense.lastReceipt > 0 && Date().timeIntervalSince(sense.receiptShownAt) < 300
    }

    private var receiptCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("回执")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
            HStack(spacing: XSpace.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(XPalette.ok)
                    .accessibilityHidden(true)
                Text("刚刚已向门锁发出 \(sense.lastReceipt) 项变更")
                    .xFont(.footnote, weight: .medium)
                    .foregroundStyle(XPalette.text)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("刚刚已向门锁发出 \(sense.lastReceipt) 项变更，撤销或变更已生效")
        }
                }
            }

    // ── 等待门锁确认的撤销 ─────────────────────────────────
    //
    // 删除凭证时，本机是立刻删的，**锁端那条要等连上锁才下发**。
    // 在此之前用户能看到的只有一句 toast「已排队从门锁上撤销」，
    // 没有地方可以核对"到底发出去没有"。
    // 这一块就是那个核对点：pending = 还没发，failed = 发了但失败。
    private var pendingCard: some View {
        XPanel(kind: .group, padding: 0) {
            VStack(spacing: 0) {
                Text("下发状态")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                HStack(spacing: XSpace.s) {
                    Text("等待门锁确认")
                        .xFont(.caption, weight: .semibold)
                        .foregroundStyle(XPalette.textTertiary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Text("\(pending.count) 条")
                        .xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.warn)
                }
                .padding(.horizontal, XSpace.card)
                .padding(.top, XSpace.m)
                .padding(.bottom, XSpace.s)

                ForEach(pending) { item in
                    HStack(spacing: XSpace.s) {
                        Image(systemName: item.state == CredQueueState.failed.rawValue
                              ? "exclamationmark.triangle.fill"
                              : "clock.arrow.circlepath")
                            .font(.system(size: XIcon.sm, weight: .medium))
                            .foregroundStyle(item.state == CredQueueState.failed.rawValue
                                             ? XPalette.danger : XPalette.warn)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .xFont(.footnote)
                                .foregroundStyle(XPalette.text)
                                .lineLimit(1)
                            Text(queueLine(item))
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.textSub)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, XSpace.card)
                    .padding(.vertical, XSpace.s)
                    .frame(minHeight: XHit.min)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.title + "，" + queueLine(item))
                }
                .padding(.bottom, XSpace.s)
            }
        }
    }

    private func queueLine(_ item: CredQueueItem) -> String {
        if item.state == CredQueueState.failed.rawValue {
            return "上次没发到门锁（第 \(max(1, item.attempt)) 次）— 连上门锁后会自动重试"
        }
        return "等待连接门锁后发出"
    }

    private var pendingOnlyCard: some View {
        XPanel(kind: .group) {
            XEmptyState(systemImage: "trash.slash",
                        title: "回收站是空的",
                        message: "但还有 \(pending.count) 条撤销没发到门锁。连上锁后会自动发出去。")
        }
    }

    // ── 动作 ───────────────────────────────────────────────
    private func reload() {
        let macs = mac.isEmpty ? DB.keychains().map { $0.mac } : [mac]
        entries = macs.flatMap { CredentialOrg.bin($0) }
            .sorted { $0.at > $1.at }
        // 只留下还没完成的 —— done 的不需要用户操心
        pending = macs.flatMap { CredentialOrg.queue($0) }
            .filter { $0.state != CredQueueState.done.rawValue }
            .sorted { $0.lastAt > $1.lastAt }
    }

    private func restore(_ e: CredBinEntry) {
        // 用 hard: false —— 主路径是"刚删完就后悔"，此时锁端删除多半还在队列里。
        // 若其实已经真删，undoRemove 返回的文字会如实说明，本页原样展示。
        let msg = CredentialOrg.undoRemove(mac, entry: e, hard: false)
        lastMessage = msg
        reload()
        SecTick.bump()      // 让主界面的成员/凭证统计跟着刷新
        XHaptics.success()
    }
}
