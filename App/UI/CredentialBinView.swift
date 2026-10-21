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

    @State private var entries: [CredentialOrg.CredBinEntry] = []
    @State private var lastMessage: String?

    private var mac: String { app.currentMac }

    private var retainDays: Int { CredentialOrg.reclaimDays() }

    var body: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                if entries.isEmpty {
                    XPanel(kind: .group) {
                        XEmptyState(systemImage: "trash.slash",
                                    title: "回收站是空的",
                                    message: "删除或停用的凭证会在这里保留 \(retainDays) 天，可以放回原位。")
                    }
                } else {
                    retentionCard
                    listCard
                }
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("凭证回收站")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert("恢复结果", isPresented: Binding(get: { lastMessage != nil },
                                               set: { if !$0 { lastMessage = nil } })) {
            Button("知道了") { lastMessage = nil }
        } message: {
            Text(lastMessage ?? "")
        }
    }

    // ── 保留期说明 ──────────────────────────────────────────
    private var retentionCard: some View {
        XPanel(kind: .group) {
            HStack(spacing: XSpace.s) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: XIcon.md, weight: .medium))
                    .foregroundStyle(XPalette.accentText)
                    .accessibilityHidden(true)
                Text("删除后保留 \(retainDays) 天。期间可以「恢复」放回原位；超过保留期会自动清理。")
                    .xFont(.system(.footnote))
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("删除后保留 \(retainDays) 天，期间可以恢复")
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

    private func row(_ e: CredentialOrg.CredBinEntry) -> some View {
        HStack(spacing: XSpace.m) {
            Image(systemName: e.fp != nil ? "touchid" : "key.fill")
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(XPalette.textSub)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.text)
                    .xFont(.system(.body))
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                Text(e.sourceName + " · " + ageText(e.at))
                    .xFont(.system(.caption))
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }
            Spacer(minLength: XSpace.s)
            Button("恢复") { restore(e) }
                .xFont(.system(.footnote, weight: .medium))
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

    // ── 动作 ───────────────────────────────────────────────
    private func reload() {
        let macs = mac.isEmpty ? DB.keychains().map { $0.mac } : [mac]
        entries = macs.flatMap { CredentialOrg.bin($0) }
            .sorted { $0.at > $1.at }
    }

    private func restore(_ e: CredentialOrg.CredBinEntry) {
        // 用 hard: false —— 主路径是"刚删完就后悔"，此时锁端删除多半还在队列里。
        // 若其实已经真删，undoRemove 返回的文字会如实说明，本页原样展示。
        let msg = CredentialOrg.undoRemove(mac, entry: e, hard: false)
        lastMessage = msg
        reload()
        SecTick.bump()      // 让主界面的成员/凭证统计跟着刷新
        XHaptics.success()
    }
}
