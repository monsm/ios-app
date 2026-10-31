// DoorScreen.swift —— 门（Tab 1）。本设计的旗舰屏。
//
// 一屏一个主角：刻度盘。它下面是这台锁的读数（电量 / 信号 / 凭证数 / 固件），
// 再下面是最新一条台账。所有数字都来自真实协议字段，没有装饰性读数。
import SwiftUI

struct DoorScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 刻度盘直径随屏宽收缩（小屏 375pt 上 260pt 会顶到读数区）。
    /// 取 min(260, 屏宽 × 0.62)：260 是设计值，0.62 保证左右各留 19% 的呼吸。
    @State private var dialSize: CGFloat = 260

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if let lock = app.lock {
                    dialBlock(lock)
                    readingsBlock(lock)
                    recentBlock
                    shortcuts
                } else {
                    noLockBlock
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("门")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.addLock))
                } label: {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字/按钮标签承载
                }
                .accessibilityLabel("添加门锁")
            }
        }
        // 进页面即从 Engine 重载（并顺带读一次 cmd03 —— 门页要看真电量/固件）。
        .task { await app.reload(refreshStatus: true) }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            dialSize = min(260, max(180, width * 0.62))
        }
        .sensoryFeedback(.success, trigger: app.dialPhase == .opened) { _, new in new }
        .sensoryFeedback(.error, trigger: app.dialPhase.isFailed) { _, new in new }
    }

    // MARK: 页头：锁名 + 连接状态（状态三通道）
    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                Text(app.lock?.name ?? "未添加门锁")
                    .font(T.F.display())
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: 0)
            }
            if let lock = app.lock {
                HStack(spacing: T.S.s) {
                    StateDot(tone: lock.isConnected ? .ok : .attention,
                             word: lock.isConnected ? "已连接" : "未连接")
                    Text(lock.isConnected ? "已连接 · \(lock.model)" : "未连接 · \(lock.model)")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 主角：刻度盘
    private func dialBlock(_ lock: LockSummary) -> some View {
        VStack(spacing: T.S.l) {
            Dial(
                phase: app.dialPhase,
                footnote: footnote,
                hint: app.dialPhase.isBusy ? "正在开锁，请不要离开" : (lock.isConnected ? "轻点开锁" : "未连接，轻点重试"),
                enabled: !app.dialPhase.isBusy
            ) {
                Task { await app.runUnlockChain() }
            }
            .environment(\.dialDiameter, dialSize)
            // 开锁成功是"一天只有几次"的高情绪时刻 —— 用 settle 档（420ms、0.95 阻尼，无过冲）。
            // 高频动作（按压/切 chip）仍走 snap 档，不能让"每天几十次"的操作变慢。
            .animation(reduceMotion ? nil : T.M.settle, value: app.dialPhase == .opened)
            .padding(.top, T.S.s)

            if case .failed(let reason) = app.dialPhase {
                HStack(spacing: T.S.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                        .font(T.F.icon(T.Icon.s))
                        .foregroundStyle(State.critical)
                    Text(reason)
                        .font(T.F.caption)
                        .foregroundStyle(State.critical)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, T.S.gutter)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var footnote: String {
        guard let at = app.lastActionAt else { return "还没有开锁记录" }
        return "上次 \(TimeFormat.ago(at))"
    }

    // MARK: 读数区：这台锁的实况
    private func readingsBlock(_ lock: LockSummary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "锁实况")
                ReadingGrid(items: [
                    .init(label: "电量", value: "\(lock.battery)", unit: "%",
                          tint: lock.battery < 20 ? State.attention : Ink.ink),
                    .init(label: "信号", value: "\(lock.signal)", unit: "/ 4",
                          tint: lock.signal <= 1 ? State.attention : Ink.ink),
                    .init(label: "凭证", value: "\(lock.keyCount)", unit: "枚"),
                    .init(label: "固件", value: lock.firmware),
                ])
                .padding(.top, T.S.xs)
                Divider().overlay(Ink.hairline)
                HStack(spacing: T.S.m) {
                    StatusLine(tone: lock.safeMode ? .attention : .neutral,
                               text: lock.safeMode ? "安全模式 开" : "安全模式 关")
                    StatusLine(tone: .neutral, text: lock.muted ? "静音 开" : "静音 关")
                }
                .padding(.top, T.S.s)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 最近一条
    private var recentBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "最近", trailing: "全部")
                if let e = app.entries.first {
                    LedgerRow(entry: e)
                } else {
                    Text("还没有记录")
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .frame(minHeight: T.Hit.min)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
        // 「最近」整块可点 → 切到台账 Tab（不是裸切：走唯一漏斗，且带 .none 上下文 = 停在台账根）。
        .contentShape(.rect)
        .onTapGesture { router.request(.tab(.records)) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "打开台账") { router.request(.tab(.records)) }
    }

    // MARK: 快捷入口（最多 4 个，不堆）
    private var shortcuts: some View {
        Panel {
            VStack(spacing: 0) {
                shortcutRow("锁实况", "gauge.with.dots.needle.50percent", .lockStatus)
                divider
                shortcutRow("新增凭证", "plus.circle", .keyCreate)
                divider
                shortcutRow("成员", "person.2", .household)
                divider
                shortcutRow("校时", "clock.arrow.circlepath", .syncTime)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var divider: some View {
        Rectangle().fill(Ink.hairline).frame(height: T.Stroke.hair)
    }

    private func shortcutRow(_ title: String, _ symbol: String, _ dest: Dest) -> some View {
        Button {
            router.request(.dest(dest))
        } label: {
            HStack(spacing: T.S.m) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.m, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .frame(width: T.Icon.xl, alignment: .leading)
                Text(title).font(T.F.body).foregroundStyle(Ink.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.s, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 空态（必须给出路）
    private var noLockBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有添加门锁",
                message: "把锁的后面板打开，长按 RESET 直到三声嘀，然后在这里添加。",
                actionTitle: "添加门锁",
                systemImage: "door.left.hand.closed"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }
}
