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

struct DiagStreamScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// 记录原始交互帧（写 `kf_debug_raw`，与 `LockService`/`HardwareService` 同键同判）。
    @State private var rawOn = DB.store.getBool("kf_debug_raw")
    /// 复制时是否带上**原始载荷**（含 skey/ekey/PIN）。默认关；本机调试时由用户显式打开。
    @State private var includeRaw = false

    /// 最新在前。
    private var lines: [DiagLogEntry] { DiagLogs.all().reversed() }

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
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gapM) {
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
                    .padding(.horizontal, V.S.cardGutter)

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
                    .padding(.horizontal, V.S.cardGutter)

                    VActionButton(title: includeRaw ? "复制原始流水（含密钥）" : "复制脱敏流水",
                                  systemImage: "doc.on.doc") {
                        let raw = LockService.shared.rawTrace
                        let text = (includeRaw ? raw.joined(separator: "\n") : exportText) + eventsText
                        Clip.set(text)
                        AppToast.shared.show(includeRaw ? "已复制 \(raw.count) 行原始流水"
                                             : "已复制 \(lines.count) 行脱敏流水", tone: .ok)
                    }
                    .disabled(includeRaw ? LockService.shared.rawTrace.isEmpty : lines.isEmpty)
                    .padding(.horizontal, V.S.cardGutter)

                    if includeRaw, LockService.shared.rawTrace.isEmpty {
                        SettingsNote(text: "内存里还没有原始流水 —— 上面的「记录原始交互帧」要先打开，"
                                     + "然后再复现一次开锁，这里才会有内容。")
                        .padding(.horizontal, V.S.cardGutter)
                    }

                    if !events.isEmpty {
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
                        .padding(.horizontal, V.S.cardGutter)
                    }

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
                        .padding(.horizontal, V.S.cardGutter)
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
                        .padding(.horizontal, V.S.cardGutter)
                    }
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("交互流水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("完成查看交互流水")
                }
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
