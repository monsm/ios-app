// LockStatusScreen.swift —— 锁实况（门 · 读数 + 校时 + 安全模式，三页合一）
//
// 这屏干什么：把 cmd03 读回的这一把锁摊成仪器读数（电量 / 信号 / 凭证 / 固件 / 型号），
//   并在同一页给出两件真正会改锁的事：**同步锁钟**（吸收原「校时」页）与**安全模式 A/B**（吸收原「安全模式」页）。
// 为什么合并（2026-11-02，见 _audit/ui-ia.md §5.1）：这三页原本各有一份「电量 / 锁钟 / 模式」读数，
//   差异只在排版密度；用户从门页点三次，看到的是同一批数。
// 数据从哪来：AppModel.lock（LockSummary）+ AppModel.lastStatus（锁钟 / verifyMode）；写入一律走 AppModel 的唯一路径。
// 主动作：同步按钮 + 两枚开关；其余控件一律墨色（契约 §3）。
import SwiftUI

/// 锁端验证模式的**唯一**文案来源。
///
/// 全仓原本有三份逐字相同的映射（锁设置 / 锁信息名片 / 安全模式说明页），
/// 任一处改判据就会与另两处分叉 —— 收在这里，新增模式只改这一处。
enum LockMode {
    /// `verifyMode` / `broadcastMode` 直接来自 cmd03 快照。传负数表示「没读到」。
    static func text(verifyMode: Int, broadcastMode: Int) -> String {
        guard verifyMode >= 0 else { return "未读到" }
        if verifyMode == 1 && broadcastMode != 0 { return "B · 双验" }
        if verifyMode == 1 { return "C · 广播+验证" }
        return "A · 单验"
    }

    /// 快照版：没读过状态时统一说「未读到」，不留空白也不猜。
    static func text(_ status: LockStatus?) -> String {
        guard let status else { return "未读到" }
        return text(verifyMode: status.verifyMode, broadcastMode: status.broadcastMode)
    }
}

struct LockStatusScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 正在下发（防重复触发）。
    @State private var writing = false
    /// 最近一次写入的回执文案。
    @State private var outcome: String?
    /// 结果行是否成功。**不再从文案里猜**（`outcome.contains("失败")` 那类判据会漏）：
    /// 例如失败文案「锁忙，请稍后再试」一个"失败/错"字都没有，却会被判成绿色。
    @State private var outcomeOK = true
    /// 每次写入（成功或失败）都 +1：`PolicyToggle` 靠它重新对齐 `isOn`。
    /// 没有它的话，写入失败时 `isOn` 不变 ⇒ `.onChange(of: isOn)` 不触发 ⇒ 开关停在
    /// 用户拨到的位置，界面显示"已开启"而锁端还是关的。
    @State private var policyRev = 0
    /// 放宽安全模式前的二次确认：放宽方向会降低校验等级（只许 A→B 变严是常态）。
    @State private var confirmRelax = false

    // MARK: 锁钟（吸收原「校时」页）

    /// 同步锁钟是否在下发中。
    @State private var syncing = false
    /// 同步结果：`ok` 决定颜色，不从文案里猜。
    @State private var syncResult: SyncResult?
    /// 上次成功校时的时刻（毫秒）。
    @State private var lastSyncedAt: Int64?

    /// 同步锁钟的一次结果。
    private struct SyncResult: Equatable {
        let ok: Bool
        let text: String
    }

    /// 自动校时阈值：偏差超过它才值得写一次（与锁信息名片的进页自动校时同一口径）。
    private static let driftThreshold = 2

    var body: some View {
        // 2026-11-02（R5 全换系统）：纯 ScrollView 换系统 List（List 不能嵌 ScrollView）。
        // 各卡用 plainRow() 抹掉行内边距/分隔线/行底色 —— 卡片外观与内部逻辑一字不动。
        // 注意：List 会接管滚动边缘效果，故不再挂 .scrollEdgeEffectStyle。
        List {
            // A 类（整宽页头）：headerRow()
            header.headerRow()
            if let lock = app.lock {
                readingsCard(lock).cardRow()
                clockCard.cardRow()
                safeModeCard.cardRow()
                policyCard(lock).cardRow()
                writeStatusCard.cardRow()
                entriesPanel.cardRow()
            } else {
                noLockPanel.cardRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(V.C.bg.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text("锁实况")
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

    private func readingsCard(_ lock: LockSummary) -> some View {
        // 电量 / 信号 / 固件三类都走 Reading（一值一处；电量由 layout-qa 已落位，此处沿用）。
        let batt = Reading.battery(app.currentMac, snapshot: lock.battery)
        let sig = Reading.signal(lock.id)
        let fw = Reading.firmware(lock.id)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "运行状态")
                // 2026-11-01 修复：`battery == -1` 是「未读到」（`AppModel:116` 的 `?? -1`），
                // 而旧写法直接渲染成「-1 %」并涂警告色 —— 与上一轮修的 `signal` 是同一类：
                // **恒定的占位值被当真值渲染**。用户看到「-1 %」只会困惑，不会知道"没读到"。
                // `signal` 侧的 0 已由 `LinkSenseModel.level` 的「不可测」语义覆盖（`levelWord` 有这个词），
                // 这里同样按「未知」渲染而不是显示数字。
                VReadingGrid(items: [
                    .init(label: "电量",
                          value: batt.text,
                          unit: batt.unit,
                          tint: batt.tone == .critical || batt.tone == .attention ? V.C.warning : V.C.text1),
                    .init(label: "信号",
                          value: sig.text,
                          unit: sig.unit,
                          tint: sig.tone == .attention ? V.C.warning : V.C.text1),
                    .init(label: "凭证", value: "\(lock.keyCount)", unit: "枚"),
                    .init(label: "固件", value: fw.text),
                ], columns: 2)
                .padding(.top, V.S.gapXS)

                hairline

                VFieldRow(label: "上次开锁", value: lastOpenText, mono: false)
                VFieldRow(label: "型号", value: lock.model, mono: false)
                VFieldRow(label: "链路", value: lock.isConnected ? "蓝牙直连" : "未建立", mono: false)
            }
        }
    }

    private var lastOpenText: String {
        guard let at = app.lastActionAt else { return "还没有开锁记录" }
        return TimeFormat.ago(at)
    }

    // MARK: 锁钟（吸收原「校时」页：偏差读数 + 一键同步 + 回读复核）

    /// 锁钟两类读数都走 Reading（协议秒 → 毫秒的换算只在 `Reading` 一处）。
    /// `Value.text == "未知"` 是 Reading 约定的「没读到」，用它判空 —— 不在这里重算一遍偏差。
    private var clockReading: Reading.Value { Reading.clockDrift(app.currentMac) }
    private var clockHasValue: Bool { clockReading.text != "未知" }

    /// 颜色随 Reading 的 tone：>60 秒才算异常（旧实现用 2 秒「值得校时」的阈值涂色，过于敏感）。
    private var clockDriftTint: Color {
        guard clockHasValue else { return V.C.text3 }
        return clockReading.tone == .attention ? V.C.warning : V.C.text1
    }

    private var clockNote: String {
        guard let d = Int(clockReading.text) else {
            return "还没读到锁钟。走近门锁、确认蓝牙开着，再点下面的「重读」。"
        }
        if d <= Self.driftThreshold {
            return "偏差在 \(Self.driftThreshold) 秒以内，不用写。临时码与时间窗凭证此刻是有效的。"
        }
        return "偏差已超过 \(Self.driftThreshold) 秒：临时码与时间窗凭证会整段失效 —— 现在同步一次。"
    }

    private var clockCard: some View {
        // 锁内时间与偏差都走 Reading（协议秒 → 毫秒的换算只在 Reading 一处）。
        // 偏差显示的是**绝对值**：Reading.clockDrift 只给量级，方向由下面 clockNote 的
        // 「现在同步一次」承担 —— 用户需要的是"要不要校时"，不是"+5 还是 -5"。
        let lockClock = Reading.lockClock(app.currentMac)
        let drift = Reading.clockDrift(app.currentMac)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "锁钟", trailing: "有效期窗口的判据")
                VReadingGrid(items: [
                    .init(label: "锁内时间", value: lockClock.text, tint: clockDriftTint),
                    .init(label: "偏差", value: drift.text, unit: drift.unit, tint: clockDriftTint),
                ], columns: 2)
                .padding(.top, V.S.gapXS)
                Text(clockNote)
                    .font(V.F.footnote)
                    .foregroundStyle(clockHasValue ? clockDriftTint : V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: syncing ? "正在同步…" : "同步门锁时间",
                              systemImage: "clock.arrow.circlepath",
                              busy: syncing) {
                    syncClock()
                }
                if let syncResult {
                    VStatusLine(tone: syncResult.ok ? .ok : .critical, text: syncResult.text)
                }
                if let lastSyncedAt {
                    Text("上次校时 · \(TimeFormat.ago(lastSyncedAt))")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                }
            }
        }
    }

    // MARK: 安全模式（吸收原「安全模式」页：一段说明 + A/B 切换）

    private var verifyMode: Int { app.lastStatus?.status.verifyMode ?? -1 }
    private var broadcastMode: Int { app.lastStatus?.status.broadcastMode ?? -1 }
    /// B 模式 = 双验（verifyMode 1 且广播非零）。C 模式本页不改，只如实标出来。
    private var isDoubleVerify: Bool { verifyMode == 1 && broadcastMode != 0 }
    private var isBroadcastVerify: Bool { verifyMode == 1 && broadcastMode == 0 }

    private var safeModeCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                // 安全模式文案的唯一来源：Reading.lockMode（内部就是 LockMode.text，传的是快照值）。
                VSectionLabel(text: "安全模式", trailing: Reading.lockMode(app.currentMac).text)
                Text("A 模式（单验）：密码、指纹或手机钥匙任一通过就能开锁，日常最快。"
                     + "B 模式（双验）：需要两种不同方式组合验证，更安全，但每次开门多一步。"
                     + "只有 A 模式下临时密码（ZOTP）才有效。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if isBroadcastVerify {
                    Text("当前是 C 模式（广播+验证）。这里只在 A / B 两档之间切换。")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: V.S.gapS) {
                    modeTag("A · 单验", selected: verifyMode == 0) { chooseSingle() }
                    modeTag("B · 双验", selected: isDoubleVerify) { chooseDouble() }
                    Spacer(minLength: 0)
                }
                .padding(.top, V.S.gapXS)
                Text("只许变严：切到 B 立即下发并回读复核；放宽回 A 要二次确认。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modeTag(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VTag(text: title, tint: selected ? V.C.blue : V.C.text3, filled: selected)
        }
        .buttonStyle(.plain)
        .disabled(writing)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// 切到 A（单验）= 放宽，先二次确认；已经是 A 就不动。
    private func chooseSingle() {
        guard isDoubleVerify else { return }
        confirmRelax = true
    }

    /// 切到 B（双验）= 变严，直接下发。
    private func chooseDouble() {
        guard !isDoubleVerify else { return }
        writeSafeMode(true)
    }

    // MARK: 锁端提示音（安全模式的开关已上移到 `safeModeCard`，这里不再重复一份）

    private func policyCard(_ lock: LockSummary) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "锁端提示音", trailing: "即点即写")
                switchRow(
                    title: "静音",
                    note: "锁端提示音关掉后，按键只给机械反馈，不发声。",
                    isOn: lock.muted,
                    onWord: "开 · 无声",
                    offWord: "关 · 有声"
                ) { on in
                    writeMuted(on)
                }
                Text("改动会立即下发到门锁，回执成功才改这一页的读数")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 写入回执：安全模式 / 静音 / 重读共用的一条状态行；没写过就不占版面。
    @ViewBuilder
    private var writeStatusCard: some View {
        if writing || outcome != nil {
            VCard {
                pendingLine
            }
        }
    }

    /// 带本地状态的政策开关：手指动作立刻反映，锁端写入结果回来后再覆盖。
    /// 为什么必须独立成视图：@State 不能声明在函数体里，而把 isOn（值快照）
    /// 直接塞进 Binding(get:set:) 会让 Toggle 拨了不动（E-O4）。
    private struct PolicyToggle: View {
        let isOn: Bool
        let onWord: String
        let offWord: String
        let write: (Bool) -> Void
        /// 父视图的写入序列号：每次写入（成功或失败）都会变。
        /// 变了就重新用 `isOn` 校准 —— 这是"写失败时开关要弹回去"的唯一可靠触发点
        /// （失败时 `isOn` 不变，`onChange(of: isOn)` 不会触发）。
        /// 声明顺序必须在 `write` 之后：调用点的实参顺序要与成员逐一初始化器一致（callsig2 会查）。
        let revision: Int

        /// 初值 false；进入时由 `.task`/onChange 从 `isOn` 播种，之后双向同步。
        /// 不用自定义 init：在 struct 的 init 里构造 State 会报「无可用初始化器」
        /// （CI 41225887928 实测）。默认值 + onAppear 播种是更稳的写法。
        @State private var localOn = false

        var body: some View {
            Toggle("", isOn: $localOn)
                .labelsHidden()
                .tint(V.C.text1)
                .accessibilityValue(localOn ? onWord : offWord)
                .onChange(of: localOn) { _, new in
                    if new != isOn { write(new) }
                }
                .onChange(of: isOn) { _, new in localOn = new }
                .onChange(of: revision) { _, _ in localOn = isOn }   // 写入结束（含失败）后对齐真实值
                .onAppear { localOn = isOn }
        }
    }

    private func switchRow(
        title: String,
        note: String,
        isOn: Bool,
        onWord: String,
        offWord: String,
        write: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: V.S.gapMS) {
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(title)
                    .font(V.F.bodyStrong)
                    .foregroundStyle(V.C.text1)
                Text(note)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isOn ? onWord : offWord)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
            }
            Spacer(minLength: V.S.gapS)
            // E-O4：`isOn` 是函数参数（值快照）。直接 `Binding(get: { isOn }, set: { write($0) })`
            // 会让 Toggle 拨动后既不前进也不回弹 —— 弱信号下（写入要几秒）用户以为开关坏了。
            // 现在交给一个独立小视图持有 @State：拨动立刻可见，写入结果回来再覆盖。
            PolicyToggle(isOn: isOn, onWord: onWord, offWord: offWord, write: write, revision: policyRev)
                .accessibilityLabel(title)
        }
        .frame(minHeight: V.Hit.min)
    }

    /// 写回执行：成功说结果，失败说原因。**不再有"待下发"** —— 写入是真的，
    /// 要么锁端确认了、要么当场报错，不留一个"本机以为改了"的中间态。
    private var pendingLine: some View {
        HStack(spacing: V.S.gapS) {
            if writing {
                ProgressView().controlSize(.small)
                Text("正在下发…").font(V.F.footnote).foregroundStyle(V.C.text2)
            } else if let outcome {
                VStateDot(tone: outcomeOK ? .ok : .attention, word: outcome)   // 用显式标志，不猜文案
                Text(outcome)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStateDot(tone: .neutral, word: "未改动")
                Text("改动会立即下发到门锁，回执成功才改这一页的读数")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("重读") { reread() }
                .font(V.F.footnote)
                .foregroundStyle(V.C.text1)
                .frame(minHeight: V.Hit.min)
                .accessibilityLabel("重新读取锁实况")
        }
        .padding(.top, V.S.gapXS)
        .accessibilityElement(children: .combine)
    }

    // MARK: 次级入口：读数不对时去哪修

    private var entriesPanel: some View {
        VCard {
            VStack(spacing: 0) {
                // 来源：原 App/UI/LockSettingsView.swift（锁设置）。
                entryRow("锁设置", "slider.horizontal.3", "临时码 / 防尾随 / 静音 / 清空密码", .lockSettings)
                hairline
                entryRow("布防", "shield.lefthalf.filled", "布防时段内，靠近门锁不会自动开门", .defend)
                hairline
                entryRow("网关", "antenna.radiowaves.left.and.right", "只看状态与告警，不能远程开门", .gateway)
            }
        }
    }

    private func entryRow(_ title: String, _ symbol: String, _ note: String, _ dest: Dest) -> some View {
        Button {
            router.request(.dest(dest))
        } label: {
            HStack(spacing: V.S.gapMS) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon18)
                    .foregroundStyle(V.C.text2)
                    .frame(width: V.Icon.xl, alignment: .leading)
                VStack(alignment: .leading, spacing: V.S.gapXXS) {
                    Text(title)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                    Text(note)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon15Medium)
                    .foregroundStyle(V.C.text3)
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)：\(note)")
    }

    // MARK: 空态（必须给出路）

    private var noLockPanel: some View {
        VCard {
            VEmptyState(
                title: "还没有门锁可以读",
                message: "读数要靠蓝牙直连才拿得到：先把锁加进来（打开后面板，长按 RESET 到三声嘀），再回这一页看电量与固件。",
                actionTitle: "添加门锁",
                systemImage: "gauge.with.dots.needle.50percent"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, V.S.gapXXL)
        }
    }

    // MARK: 写入

    /// 同步锁钟：把手机当前时间写进锁，再回读复核。回读偏差没归零就如实说没归零。
    private func syncClock() {
        guard app.lock != nil, !syncing else { return }
        syncing = true
        syncResult = nil
        Task {
            let r = await app.syncTime()
            syncing = false
            switch r {
            case .failure(let e):
                let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
                syncResult = SyncResult(ok: false, text: "同步失败：\(msg)")
            case .success(let pair):
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                lastSyncedAt = now
                // 与门页「超 30 天未校时」提醒卡同一真值：落盘，不只留内存。
                DB.saveSyncTime(app.currentMac, Double(now))
                // `pair.1` 是「锁 − 手机」的偏差（秒）；本页上面算的是「手机 − 锁」，取反才同号。
                let residual = -pair.1
                syncResult = SyncResult(ok: abs(residual) <= Self.driftThreshold,
                                        text: "同步完成 · 回读偏差 \(residual) 秒")
            }
        }
    }

    /// 安全模式：真链路 cmd20 SETVALIDATIONMODE（1 = 双验）。回包 rc=0 才回写。
    private func writeSafeMode(_ on: Bool) {
        guard app.lock != nil, !writing else { return }
        writing = true
        Task {
            let r = await app.setSafeMode(on)
            writing = false
            policyRev += 1
            if case .failure(let e) = r {
                outcomeOK = false
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcomeOK = true
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
            policyRev += 1
            if case .failure(let e) = r {
                outcomeOK = false
                outcome = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                outcomeOK = true
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
            outcomeOK = app.lastError == nil
            outcome = app.lastError == nil ? "已重新读取锁实况" : app.lastError
            app.lastError = nil
        }
    }

    private var hairline: some View {
        Divider()
    }
}
