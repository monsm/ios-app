// 运行日志/诊断 — 汇总运行状态与日志, 一键复制发给开发者排障
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject var app: AppState
    @State private var debugRaw = DB.store.getBool("kf_debug_raw")
    @State private var copied = false
#if DEBUG
    @State private var seeded = BreakFixture.isSeeded()
#endif

    var body: some View {
        Form {
            Section("诊断报告") {
                Button {
                    UIPasteboard.general.string = report()
                    copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack {
                        Label(copied ? "已复制, 请粘贴发给开发者" : "复制全部诊断信息",
                              systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                // 状态不只靠颜色: 图标在 checkmark.circle / doc.on.doc 之间切换, 且播报给 VoiceOver
                .foregroundStyle(copied ? DS.Palette.ok : DS.Palette.accentText)
                .accessibilityLabel(copied ? "已复制, 请粘贴发给开发者" : "复制全部诊断信息")
                .accessibilityValue(copied ? "已复制到剪贴板" : "")
                Text("报告包含: 应用/系统版本、当前门锁信息、最近 100 条运行日志。回到对话窗口直接粘贴即可。")
                    .font(.caption).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("记录原始收发 hex", isOn: Binding(
                    get: { debugRaw },
                    set: { DB.store.set("kf_debug_raw", $0); debugRaw = $0}))
            } footer: {
                Text("协议联调时开启 (日志会带原始帧 hex); 平时关闭。")
            }
            // 包2/128 环境拥挤度: 冷启动扫描可见设备数的本地结论
            Section {
                LabeledRow("环境拥挤度 (128)", LinkSense.envConclusion())
            } footer: {
                Text("按最近一次冷启动扫描的可见 BLE 设备数本地判断, 不精确测扫描耗时。")
                    .font(.caption)
            }
            // 包2/72 断连原因行: BLE 断连/握手失败事件翻译成人话按时间列出 (数据源 BleTelemetry 流水)
            Section("断连与失败 (72)") {
                if BleTelemetry.events.isEmpty {
                    Text("暂无断连事件 — 连接全程顺畅。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(BleTelemetry.events.prefix(20)) { ev in
                        LabeledRow(ev.what, ev.ok ? "成功" : friendlyFailReason(ev.what))
                    }
                }
            }
            // 133 蓝牙堆栈急救: 连续 GATT/连接失败后给出 关开蓝牙/重启手机 分步指引
            if failsInLast20 >= 3 {
                Section("蓝牙急救 (133)") {
                    LabeledRow("第 1 步", "到 控制中心 关闭再打开系统蓝牙, 等 10 秒回设备页")
                    LabeledRow("第 2 步", "仍失败: 到 设置 → 蓝牙 关闭 App 后台后重新打开本 App")
                    LabeledRow("第 3 步", "仍失败: 重启手机后再试 (蓝牙堆栈异常的重启大法)")
                } footer: {
                    Text("近 20 条断连事件中有 \(failsInLast20) 条失败 — 建议按序执行。")
                        .font(.caption)
                }
            }
#if DEBUG
            // break-ui: 注入最坏数据一次性检验长名/长备注/无时间日志/告警行是否撑爆布局,
            // 一键清除。绝不进 Release。
            // 带 footer 的 Section 必须用 content/header/footer 三段式重载,
            // 不存在 Section("标题") { } footer: { } 这种写法
            Section {
                // 标签必须由 @State 驱动: set 里只做副作用不改状态的话, 开关文案不会翻转
                Toggle(seeded ? "清除最坏数据" : "注入最坏数据",
                       isOn: Binding(get: { seeded },
                                     set: { on in
                                         seeded = on
                                         on ? BreakFixture.seed() : BreakFixture.clear()
                                         app.loadDevices()   // 让注入的门锁立即出现在设备列表
                                     }))
            } header: {
                Text("布局压力自检 (仅 DEBUG)")
            } footer: {
                Text("注入一台名字超长、备注超长、含无时间戳与告警行的测试门锁，用来人工走查各界面在极端数据下是否破版。")
            }
            #endif
            Section("运行日志 (最新在末尾)") {
                if logRows.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Image(systemName: "tray")
                            .font(.system(size: DS.Icon.md))
                            .foregroundStyle(DS.Palette.accentText)
                            .accessibilityHidden(true)
                        Text("暂无日志 — 做一次连接/开锁/读取操作后这里会出现记录。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DS.Space.xs)
                    .accessibilityElement(children: .combine)
                }
                ForEach(logRows) { row in
                    Text(row.line)
                        .font(.caption.monospaced())
                        .foregroundStyle(DS.Palette.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("运行日志")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private struct LogLine: Identifiable {
        let id: String
        let line: String
    }

    /// id 由"日志内容 + 同内容出现次序"构成: 顶部插入新日志时已有行的 id 不变,
    /// 不会像 id: \.offset 那样把所有行的 key 整体位移 (长按选中会跳)。
    private var logRows: [LogLine] {
        var seen: [String: Int] = [:]
        var out: [LogLine] = []
        out.reserveCapacity(150)
        for line in app.lock.logs.suffix(150) {
            let n = seen[line] ?? 0
            seen[line] = n + 1
            out.append(LogLine(id: line + "#" + String(n), line: line))
        }
        return out
    }

    /// 133: 近 20 条断连事件中的失败条数 (≥3 触发急救块)
    private var failsInLast20: Int { BleTelemetry.events.prefix(20).filter { !$0.ok }.count }

    /// 72: 断连错误码人话翻译 (本地词表, 不改协议层; 124 占用类走保守文案)
    private func friendlyFailReason(_ what: String) -> String {
        if what.contains("超时") { return "握手超时 — " + LinkSense.occupationHint() }
        if what.contains("蓝牙") { return "蓝牙未开/权限缺失 — 系统设置 → 隐私与安全性 → 蓝牙" }
        if what.contains("未发现") { return "不在广播范围 — 走近门锁 1 米内再试" }
        if what.contains("信号弱") { return "RSSI 低于围栏, 本轮跳过预热 (省电策略)" }
        if what.contains("回连") { return "回连轮次失败 — 按 5/15/30/60/90 秒节律重试中" }
        if what.contains("重协商") { return "会话重协商 — 连接挂起过久, 已主动重建握手" }
        return "失败 — 详见运行日志与失败三分类 (536)"
    }

    private func report() -> String {
        var out = "【离线锁管家诊断报告】\n"
        out += "时间: " + DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium) + "\n"
        out += "App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))\n"
        out += "系统: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)\n"
        if let kc = app.current {
            out += "门锁: \(app.displayName) / mac=\(kc.mac) / pid=\(kc.pid) / 固件=\(kc.fw.isEmpty ? app.snapshot?.firmware ?? "未知" : kc.fw)\n"
            out += "连接: \(app.lock.connectedMAC == kc.mac ? "已连接" : "未连接")\n"
        } else {
            out += "门锁: 未配对\n"
        }
        if !app.lock.lastError.isEmpty { out += "最近错误: \(app.lock.lastError)\n" }
        out += "--- 运行日志 (\(app.lock.logs.count) 条) ---\n"
        out += app.lock.logs.suffix(100).joined(separator: "\n")
        return out
    }
}