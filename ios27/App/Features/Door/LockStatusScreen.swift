// LockStatusScreen.swift —— 锁实况（门 · 读数页）
//
// 这屏干什么：把 cmd03 读回的这一把锁摊成仪器读数（电量 / 信号 / 凭证 / 固件 / 型号），
// 并把两枚真的能改的锁端策略摆在同一页：安全模式（cmd20，只许变严）与静音（cmd18）。
// 数据从哪来：AppModel.lock（LockSummary）；本机"待下发"记账来自这一页的写入。
// 主动作：本屏不放 signal 填充按钮 —— 主动作就是这两枚开关，其余控件一律墨色（契约 §3）。
import SwiftUI

struct LockStatusScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 正在下发（防重复触发）。
    @State private var writing = false
    /// 最近一次写入的回执文案。
    @State private var outcome: String?
    /// 放宽安全模式前的二次确认：放宽方向会降低校验等级（只许 A→B 变严是常态）。
    @State private var confirmRelax = false

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if let lock = app.lock {
                    readingsPanel(lock)
                    policyPanel(lock)
                    entriesPanel
                } else {
                    noLockPanel
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("锁实况")
        .navigationBarTitleDisplayMode(.inline)
        .alert("放宽安全模式？", isPresented: $confirmRelax) {
            Button("取消") { }
            Button("放宽") { writeSafeMode(false) }
        } message: {
            Text("A / B 模式决定这道锁验一次还是两次。放宽后一枚凭证就能单独开门，请确认你此刻就在门内。")
        }
    }

    // MARK: 页头：大标题 + 一行状态（形状 + 颜色 + 文字三通道）

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("锁实况")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
            HStack(spacing: T.S.s) {
                StateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    // 状态行最多两行：宁可换行，不要截断或缩字（缩字会把 13pt 压到 10pt，低于可读下限）
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
    }

    private var headerTone: Tone {
        guard let lock = app.lock else { return .neutral }
        return lock.isConnected ? .ok : .attention
    }

    private var headerWord: String {
        guard let lock = app.lock else { return "未添加" }
        return lock.isConnected ? "已连接" : "未连接"
    }

    private var headerText: String {
        guard let lock = app.lock else { return "还没有门锁可以读" }
        return lock.isConnected ? "\(lock.name) · \(lock.model)" : "\(lock.name) · 走近门锁再读"
    }

    // MARK: 主角：这台锁的读数

    private func readingsPanel(_ lock: LockSummary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "运行状态", trailing: "cmd03")
                ReadingGrid(items: [
                    .init(label: "电量", value: "\(lock.battery)", unit: "%",
                          tint: lock.battery <= 20 ? State.attention : Ink.ink),
                    .init(label: "信号", value: "\(lock.signal)", unit: "/ 4",
                          tint: lock.signal <= 1 ? State.attention : Ink.ink),
                    .init(label: "凭证", value: "\(lock.keyCount)", unit: "枚"),
                    .init(label: "固件", value: lock.firmware),
                ], columns: 2)
                .padding(.top, T.S.xs)

                hairline

                FieldRow(label: "上次开锁", value: lastOpenText, mono: false)
                FieldRow(label: "型号", value: lock.model, mono: false)
                FieldRow(label: "链路", value: lock.isConnected ? "蓝牙直连" : "未建立", mono: false)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var lastOpenText: String {
        guard let at = app.lastActionAt else { return "还没有开锁记录" }
        return TimeFormat.ago(at)
    }

    // MARK: 锁端策略：两枚开关就是本屏的主动作

    private func policyPanel(_ lock: LockSummary) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "锁端策略", trailing: "即点即写")
                switchRow(
                    title: "安全模式",
                    note: "A / B 模式决定验一次还是两次。只许变严；放宽要二次确认。",
                    isOn: lock.safeMode,
                    onWord: "开 · 双验",
                    offWord: "关 · 单验"
                ) { on in
                    if on { writeSafeMode(true) } else { confirmRelax = true }
                }

                hairline

                switchRow(
                    title: "静音",
                    note: "锁端提示音关掉后，按键只给机械反馈，不发声。",
                    isOn: lock.muted,
                    onWord: "开 · 无声",
                    offWord: "关 · 有声"
                ) { on in
                    writeMuted(on)
                }

                pendingLine
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func switchRow(
        title: String,
        note: String,
        isOn: Bool,
        onWord: String,
        offWord: String,
        write: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: T.S.m) {
            VStack(alignment: .leading, spacing: T.S.xxs) {
                Text(title)
                    .font(T.F.bodyStrong)
                    .foregroundStyle(Ink.ink)
                Text(note)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? onWord : offWord)
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
            }
            Spacer(minLength: T.S.s)
            Toggle(title, isOn: Binding(get: { isOn }, set: { write($0) }))
                .labelsHidden()
                .tint(Ink.ink)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? onWord : offWord)
        }
        .frame(minHeight: T.Hit.min)
    }

    /// 写回执行：成功说结果，失败说原因。**不再有"待下发"** —— 写入是真的，
    /// 要么锁端确认了、要么当场报错，不留一个"本机以为改了"的中间态。
    private var pendingLine: some View {
        HStack(spacing: T.S.s) {
            if writing {
                ProgressView().controlSize(.small)
                Text("正在下发…").font(T.F.caption).foregroundStyle(Ink.inkSub)
            } else if let outcome {
                StateDot(tone: outcome.contains("失败") || outcome.contains("错") ? .attention : .ok, word: outcome)
                Text(outcome)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                StateDot(tone: .neutral, word: "未改动")
                Text("改动会立即下发到门锁，回执成功才改这一页的读数")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("重读") { reread() }
                .font(T.F.caption)
                .foregroundStyle(Ink.ink)
                .frame(minHeight: T.Hit.min)
                .accessibilityLabel("重新读取锁实况")
        }
        .padding(.top, T.S.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: 次级入口：读数不对时去哪修

    private var entriesPanel: some View {
        Panel {
            VStack(spacing: 0) {
                // 来源：原 App/UI/LockSettingsView.swift（锁设置）。
                entryRow("锁设置", "slider.horizontal.3", "临时码开关 / 自动上锁 / 清空密码", .lockSettings)
                hairline
                entryRow("校时", "clock.arrow.circlepath", "锁钟偏了，临时码与时间窗凭证会失效", .syncTime)
                hairline
                entryRow("布防", "shield.lefthalf.filled", "布防时段内，靠近门锁不会自动开门", .defend)
                hairline
                entryRow("网关", "antenna.radiowaves.left.and.right", "只看状态与告警，不能远程开门", .gateway)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func entryRow(_ title: String, _ symbol: String, _ note: String, _ dest: Dest) -> some View {
        Button {
            router.request(.dest(dest))
        } label: {
            HStack(spacing: T.S.m) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.m, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .frame(width: T.Icon.xl, alignment: .leading)
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text(title)
                        .font(T.F.body)
                        .foregroundStyle(Ink.ink)
                    Text(note)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .accessibilityLabel("\(title)：\(note)")
    }

    // MARK: 空态（必须给出路）

    private var noLockPanel: some View {
        Panel {
            EmptyPanel(
                title: "还没有门锁可以读",
                message: "读数要靠蓝牙直连才拿得到：先把锁加进来（打开后面板，长按 RESET 到三声嘀），再回这一页看电量与固件。",
                actionTitle: "添加门锁",
                systemImage: "gauge.with.dots.needle.50percent"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 写入

    /// 安全模式：真链路 cmd20 SETVALIDATIONMODE（1 = 双验）。回包 rc=0 才回写。
    private func writeSafeMode(_ on: Bool) {
        guard app.lock != nil, !writing else { return }
        writing = true
        Task {
            let r = await app.setSafeMode(on)
            writing = false
            if case .failure(let e) = r {
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcome = on ? "已切到双验（A/B 模式）" : "已切回单验"
            }
        }
    }

    /// 静音：真链路 cmd18（vol 1B：0 = 有声 / 1 = 静音）。
    private func writeMuted(_ on: Bool) {
        guard app.lock != nil, !writing else { return }
        writing = true
        Task {
            let r = await app.setMuted(on)
            writing = false
            if case .failure(let e) = r {
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcome = on ? "已静音：键盘与开锁不提示音" : "已恢复提示音"
            }
        }
    }

    /// 读一次锁状态（cmd03），刷新这一页的全部读数。
    private func reread() {
        guard !writing else { return }
        writing = true
        Task {
            await app.refreshStatus()
            writing = false
            outcome = app.lastError == nil ? "已重新读取锁实况" : app.lastError
            app.lastError = nil
        }
    }

    private func copy(_ lock: LockSummary, safeMode: Bool, muted: Bool) -> LockSummary {
        LockSummary(
            id: lock.id,
            name: lock.name,
            model: lock.model,
            battery: lock.battery,
            signal: lock.signal,
            firmware: lock.firmware,
            keyCount: lock.keyCount,
            isConnected: lock.isConnected,
            safeMode: safeMode,
            muted: muted
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
    }
}
