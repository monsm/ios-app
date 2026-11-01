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
//   所以这里展示与复制的都是**经 `FrameRedact` 脱敏**的文本：只留 8 字节帧头（命令号 + 长度），
//   载荷整段替换成 `…(N bytes 已脱敏)`。
//   完整帧只留在内存 `recentFrames`（不落盘、不复制），与既有纪律一致。
import SwiftUI

struct DiagStreamScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// 记录原始交互帧（写 `kf_debug_raw`，与 `LockService`/`HardwareService` 同键同判）。
    @State private var rawOn = DB.store.getBool("kf_debug_raw")

    /// 最新在前。
    private var lines: [DiagLogEntry] { DiagLogs.all().reversed() }

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

                    VActionButton(title: "复制全部流水", systemImage: "doc.on.doc") {
                        Clip.set(exportText)
                        AppToast.shared.show("已复制 \(lines.count) 行", tone: .ok)
                    }
                    .disabled(lines.isEmpty)
                    .padding(.horizontal, V.S.cardGutter)

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
    }
}
