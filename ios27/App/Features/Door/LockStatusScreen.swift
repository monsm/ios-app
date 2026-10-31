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

    /// 本机已记下、还没下发到锁的写项（靠锁时自动补发，见 device.link.resync）。
    @State private var pendingWrites: Set<String> = []
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    private var pendingLine: some View {
        HStack(spacing: T.S.s) {
            StateDot(tone: pendingWrites.isEmpty ? .neutral : .attention,
                     word: pendingWrites.isEmpty ? "无待下发" : "待下发")
            Text(pendingWrites.isEmpty ? "本机记录与锁端一致" : "改动已记在本机，靠锁时补发")
                .font(T.F.caption)
                .foregroundStyle(pendingWrites.isEmpty ? Ink.inkSub : State.attention)
                .fixedSize(horizontal: false, vertical: true)
            if !pendingWrites.isEmpty {
                Reading(value: "\(pendingWrites.count)", unit: "项", size: 13, tint: State.attention, animated: false)
            }
            Spacer(minLength: 0)
            if !pendingWrites.isEmpty {
                Button("重试") { retryPending() }
                    .font(T.F.caption)
                    .foregroundStyle(Ink.ink)
                    .frame(minHeight: T.Hit.min)
                    .accessibilityLabel("重试下发待写项")
            }
        }
        .padding(.top, T.S.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: 次级入口：读数不对时去哪修

    private var entriesPanel: some View {
        Panel {
            VStack(spacing: 0) {
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
                    .font(.system(size: T.Icon.m, weight: .regular))
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
                    .font(.system(size: T.Icon.s, weight: .medium))
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

    private func writeSafeMode(_ on: Bool) {
        guard let lock = app.lock else { return }
        // TODO(engine): 真实链路是 cmd20 SETVALIDATIONMODE（1 = 双验）；回包 rc=0 才回写锁端状态。
        // 这里只改本机记录并标"待下发"，不假装锁端已经变严。
        app.lock = copy(lock, safeMode: on, muted: lock.muted)
        pendingWrites.insert("安全模式")
    }

    private func writeMuted(_ on: Bool) {
        guard let lock = app.lock else { return }
        // TODO(engine): 真实链路是 cmd18（vol 1B：0 = 有声 / 1 = 静音）。
        app.lock = copy(lock, safeMode: lock.safeMode, muted: on)
        pendingWrites.insert("静音")
    }

    /// 待下发项的重试出口：真的去补发一次，成功就把账清掉。
    private func retryPending() {
        // TODO(engine): 真实链路是 ensureConnected → 逐项补发（cmd20 / cmd18）→ 按回执清队列。
        guard let lock = app.lock else { return }
        if lock.isConnected {
            pendingWrites.removeAll()
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
