// DiagStreamScreen.swift —— 与门锁交互的**原始流水**（排障用，可复制）。
//
// 为什么有这个页面：
//   · `LockService.log()` 每一行都会落进 `DiagLogs`（持久、按天保留），
//     但**全仓没有任何界面读它** —— `DiagLogs.entries/all()/today()` 零消费者；
//   · 而 TX/RX 的 `hex=` 行原本被 `debugRaw` 挡着，那个开关**也没有 UI**（只能外部改 defaults）。
//   结果是：用户遇到"开锁失败"时，**无法把现场交互复制出来**。
//
// 安全边界（必须有，不能妥协）：
//   帧里携带 skey（cmd05 换钥）/ 密码（cmd0A）/ PIN / ekey —— 都是开锁凭据。
//
//   2026-11-01（Round 311）核实并更正：本条此前写「完整帧只留在内存、**不复制**」——
//   **与实现相反**。现在有两条路，头注必须如实写清：
//
//   ① 默认：展示与复制都走 `FrameRedact` —— 只留 8 字节帧头（命令号 + 长度），
//      载荷整段替换成 `…(N bytes 已脱敏)`。
//   ② 用户显式打开「包含原始载荷（含密钥，勿外传）」后：复制的是 `LockService.rawTrace` 里的**原始帧**，
//      其中含 skey / ekey / PIN 明文。走 `Clip.set`（**90 秒后剪贴板自动过期**），
//      不落盘、不进备份、不进任何导出 —— 仅限本机调试，这一点 UI 上也是这么写的。
//
//   所以准确的表述是：**完整帧不会主动离开本机，但用户可以在知情的前提下复制它（限时 90 秒）。**
import SwiftUI


/// List 里的「整块卡片」行（与其它 List 化页面同用途）。独立命名，避免同名扩展重声明。
private extension View {
    func diagCardRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).plainRow()
    }
}
struct DiagStreamScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    /// 记录原始交互帧（写 `kf_debug_raw`，与 `LockService`/`HardwareService` 同键同判）。
    @State private var rawOn = DB.store.getBool("kf_debug_raw")
    /// 复制时是否带上**原始载荷**（含 skey/ekey/PIN）。默认关；本机调试时由用户显式打开。
    @State private var includeRaw = false
    /// 2026-11-02（用户要求）：落盘条数上限档位 + 清空确认。
    /// 原来写死 500 行 —— 一次开锁十几行，复现两三轮就把现场滚掉了。
    @State private var maxLines = DiagLogs.maxLines
    @State private var askClear = false
    /// 界面最多渲染多少行：与落盘上限同步，但「不限」档为了不卡界面仍截到 5000。
    /// 流水是 LazyVStack，理论上不限也行；这里设硬顶是因为一次全渲染 2 万行会让这一页明显卡。
    private var shownLines: [DiagLogEntry] {
        let all = DiagLogs.all().reversed()
        let cap = maxLines > 0 ? maxLines : 5000
        return Array(all.prefix(cap))
    }

    /// List 段头：中文必须显式 textCase(nil)，否则系统会把段头拉成大写形态。
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(V.F.small)
            .foregroundStyle(V.C.text3)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    /// 最新在前。渲染与复制都走 `shownLines`（受上限档位约束）。
    private var lines: [DiagLogEntry] { shownLines }

    /// 事件台账（`BleTelemetry.recordEvent`）—— 这些**一直是只写不读**：
    /// 备份跳过非法密钥、台账解不出、钥匙串写失败、恢复时归属找不到…… 全记在这，却没有任何界面显示。
    /// 它们不含密钥（只写"发生了什么"），所以两种复制模式都带上。
    private var events: [BleEvent] { Array(BleTelemetry.events.prefix(40)) }

    private var eventsText: String {
        guard !events.isEmpty else { return "" }
        return "\n\n=== 事件台账 ===\n" + events.map { "\($0.at) [\($0.ok ? "OK" : "!!")] \($0.what)" }.joined(separator: "\n")
    }

    private var exportText: String {
        lines.map { "\($0.date) \($0.time) [\($0.level)] \($0.msg)" }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            // 2026-11-02（R5 全换系统）：ScrollView + VStack → 系统 List + Section。
            // ⚠ `.captureShield` **留在外层**（与改前同一位置）：这一页在「包含原始载荷」时
            // 是完整 TX/RX 帧（含 skey / PIN / ekey 明文 hex），录屏/截图必须遮挡。
            // 流水本身仍放在卡片里（它是等宽多行的连续文本，不是一组可点的行），
            // 拆成 List 行会让「一次会话的连续帧」被行分隔线切碎，排障时更难读。
            // 业务逻辑、写盘键、禁用态、无障碍标签一字未改。
            List {
                Section {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VCardHeader(title: "记录原始交互帧")
                            Toggle(isOn: $rawOn) {
                                Text("记录每条命令的 TX / RX 帧头")
                                    .font(V.F.body)
                                    .foregroundStyle(V.C.text1)
                            }
                            .tint(V.C.rewardBlue)
                            .onChange(of: rawOn) { _, v in DB.store.set("kf_debug_raw", v) }
                            SettingsNote(text: "帧头包含命令号与长度，对排查「到底哪一步失败」够用。" +
                                         "载荷（skey / PIN / ekey / 密码）会自动脱敏 —— 这是有意的：" +
                                         "完整帧一旦可复制，等于把开锁凭据交出去。")
                        }
                    }
                    .diagCardRow()
                } header: {
                    sectionHeader("记录范围")
                }

                // 2026-11-02（用户要求）：日志上限 + 清空。
                // 「清空」的价值：出问题时先清、再复现，日志里就只剩这一次现场 ——
                // 比在几百行里翻找第一帧要快得多。清空是破坏性动作，所以要二次确认。
                Section {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VCardHeader(title: "保留行数")
                            Picker("保留行数", selection: Binding(
                                get: { maxLines },
                                set: { v in
                                    maxLines = v
                                    DB.store.setInt(DiagLogs.maxKey, v)
                                }
                            )) {
                                ForEach(DiagLogs.maxChoices, id: \.value) { c in
                                    Text(c.label).tag(c.value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            SettingsNote(text: maxLines == 0
                                         ? "不限行数 —— 只受「保留天数」约束。行数太多会让这一页变慢，也更容易把旧现场混进来。"
                                         : "落盘保留最近 \(maxLines) 行。一次开锁约十几行，复现两三轮就会滚掉最早的帧；要保现场请调大或选「不限」。")
                        }
                    }
                    .diagCardRow()

                    VActionButton(title: "清空流水（\(lines.count) 行）", systemImage: "trash", tint: V.C.critical) {
                        askClear = true
                    }
                    .disabled(lines.isEmpty)
                    .diagCardRow()
                } header: {
                    sectionHeader("上限与清空")
                }

                Section {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            VCardHeader(title: "复制内容")
                            Toggle(isOn: $includeRaw) {
                                Text("包含原始载荷（含密钥，勿外传）")
                                    .font(V.F.body)
                                    .foregroundStyle(V.C.text1)
                            }
                            .tint(V.C.critical)
                            SettingsNote(text: includeRaw
                                         ? "当前复制的是**内存里的原始帧**：里面含 skey / ekey / PIN / 密码明文。"
                                           + "只用于本机调试，不要发到公开渠道。App 不会把它落盘或写进备份。"
                                         : "默认复制的是**脱敏**版本：保留帧头与 KLV 结构（字段号 + 长度），载荷值遮掉。"
                                           + "排查「结构对不对」够用，也方便直接贴出来。")
                        }
                    }
                    .diagCardRow()

                    VActionButton(title: includeRaw ? "复制原始流水（含密钥）" : "复制脱敏流水",
                                  systemImage: "doc.on.doc") {
                        let raw = LockService.shared.rawTrace
                        let text = (includeRaw ? raw.joined(separator: "\n") : exportText) + eventsText
                        Clip.set(text)
                        AppToast.shared.show(includeRaw ? "已复制 \(raw.count) 行原始流水"
                                             : "已复制 \(lines.count) 行脱敏流水", tone: .ok)
                    }
                    .disabled(includeRaw ? LockService.shared.rawTrace.isEmpty : lines.isEmpty)
                    .diagCardRow()

                    if includeRaw, LockService.shared.rawTrace.isEmpty {
                        SettingsNote(text: "内存里还没有原始流水 —— 上面的「记录原始交互帧」要先打开，"
                                     + "然后再复现一次开锁，这里才会有内容。")
                        .diagCardRow()
                    }

                    // 2026-11-02（用户要求）：**只贴流水看不出锁端认什么**。
                    // rc=2 这类「凭证被拒」必须两边一起看：锁端 PIN 容量/存量、剩余可验证次数，
                    // 对本机 PIN 池条数、存的那枚 ekey 里嵌的 PIN。这个按钮一次给出全部。
                    // 它**不含密钥明文**（skey/ekey/PIN 只打指纹），可以安全贴出来。
                    VActionButton(title: "复制双侧快照（锁端 + 本机，无密钥明文）", systemImage: "square.on.square") {
                        let snap = DiagSnapshot.build(mac: app.currentMac)
                        Clip.set(snap)
                        AppToast.shared.show("已复制双侧快照（\(snap.split(separator: "\n").count) 行）", tone: .ok)
                    }
                    .disabled(app.currentMac.isEmpty)
                    .diagCardRow()
                } header: {
                    sectionHeader("复制")
                }

                if !events.isEmpty {
                    Section {
                        VCard {
                            VStack(alignment: .leading, spacing: V.S.gapXS) {
                                VCardHeader(title: "事件台账（\(events.count) 条）")
                                // 用 enumerated 而不是 ForEach(events)：`BleEvent.id` = at+what+ok，
                                // 同一分钟内重复发生的事件会产生重复 id（SwiftUI 未定义行为）。
                                ForEach(Array(events.enumerated()), id: \.offset) { pair in
                                    Text("\(pair.element.at)  \(pair.element.what)")
                                        .font(V.F.stamp)
                                        .foregroundStyle(pair.element.ok ? V.C.text2 : V.C.warning)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .diagCardRow()
                    } header: {
                        sectionHeader("事件台账")
                    }
                }

                Section {
                    if lines.isEmpty {
                        VCard {
                            VStack(alignment: .leading, spacing: V.S.gapXS) {
                                Text("还没有交互流水")
                                    .font(V.F.rowTitle)
                                    .foregroundStyle(V.C.text1)
                                Text("先去「门」页开一次门（或点一次读取），再回到这里。")
                                    .font(V.F.footnote)
                                    .foregroundStyle(V.C.text3)
                            }
                        }
                        .diagCardRow()
                    } else {
                        VCard {
                            LazyVStack(alignment: .leading, spacing: V.S.gapXS) {
                                ForEach(lines) { e in
                                    Text("\(e.time) [\(e.level)] \(e.msg)")
                                        .font(V.F.stamp)   // 等宽 12pt —— 时间戳/命令号对齐好读
                                        .foregroundStyle(e.level == "error" ? V.C.critical
                                                         : (e.level == "warn" ? V.C.warning : V.C.text2))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .diagCardRow()
                    }
                } header: {
                    sectionHeader("流水（\(lines.count) 行，最新在前）")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(V.S.gap16)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, V.S.gap16, for: .scrollContent)
            .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
            .background(CanvasBackground())
            .navigationTitle("交互流水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("完成查看交互流水")
                }
            }
            // 清空是破坏性动作：先问，再清。清掉的是**本机诊断流水**，不碰锁端日志、不碰台账。
            .confirmationDialog("清空全部交互流水？", isPresented: $askClear, titleVisibility: .visible) {
                Button("清空 \(lines.count) 行", role: .destructive) {
                    let n = DiagLogs.clear()
                    maxLines = DiagLogs.maxLines
                    AppToast.shared.show("已清空 \(n) 行交互流水", tone: .ok)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只清本机这一份流水，不动锁内日志、不动台账、不动钥匙串。清完后复现一次，留下的就只有那一次的现场。")
            }
        }
        // 2026-11-01（Round 310）：**这一页是全 App 最敏感的一页** —— 打开「包含原始载荷」时，
        // `rawTrace` 里是完整 TX/RX 帧（含 skey / PIN / ekey 明文 hex）。
        // 而它此前没有任何遮挡：录屏、截图、应用切换器快照都能原样带走母钥。
        // 与凭证详情 / 动态码 / 二维码 / 备份那四处同一处置（Round 309 又补了后台快照那一路）。
        .captureShield(rawOn ? "这里含原始交互帧（母钥 / PIN / ekey）\n屏幕正在被录制或截图，已遮挡"
                             : "这里是与门锁的交互流水\n屏幕正在被录制或截图，已遮挡")
    }
}
