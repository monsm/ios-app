// 记录页的 3 个独立 Sheet（告警类型 / 活跃凭证 / 出窗提醒）
// 2026-10-29 从 RecordsView.swift（2203 行）拆出 —— 都是独立 struct，只依赖全局类型，无 private 边界。
import SwiftUI

// ---------- 565 告警类型多选面板 ----------
/// 对勾列表按库里**实际**告警类型渲染 (StatsKit.alarmTypes 两类)。原句列了"胁迫", 但协议日志
/// 类型表没有胁迫类 (与 725 判 ❌ 同一理由) —— 不虚构一个查不到的类型, 也在面板里把这件事写明。
/// 选中集直接绑定 filters.alarmKinds (空 = 不限类型; 选中数回显在打开的 chip 上)。
struct AlarmKindsSheet: View {
    @Binding var sel: Set<Int>
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StatsKit.alarmTypes.sorted(), id: \.self) { t in
                        Button {
                            DS.Haptics.tick.impactOccurred()
                            if sel.contains(t) { sel.remove(t) } else { sel.insert(t) }
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Text(RecordVerbs.alarmVerb[t] ?? String(t))
                                    .vkFont(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                Spacer(minLength: 0)
                                Image(systemName: sel.contains(t) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(sel.contains(t) ? DS.Palette.accentText : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RecordVerbs.alarmVerb[t] ?? String(t))
                        .accessibilityAddTraits(sel.contains(t) ? .isSelected : [])
                    }
                } header: {
                    Text("只看选中的类型 · 已选 \(sel.count) 项")   // 565 只看选中的类型
                } footer: {
                    Text("不选 = 不限类型。列表按锁端日志实际有的告警类型给出; 协议无「胁迫」类告警, 不列。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("告警类型")   // 565 告警类型
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { sel.removeAll() }
                        .disabled(sel.isEmpty)
                }
            }
        }
    }
}

// ---------- 包9/574 活跃凭证排序 (台账近 30 天推断, 一律标"约") ----------
struct ActiveCredsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.current == nil {
                        Text("还没有添加门锁。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } else {
                        ForEach(Array(RecordSearch.activeCredentials(mac: app.currentMac).enumerated()), id: \.offset) { i, c in
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: Self.icon(c.kind))
                                    .font(.system(size: DS.Icon.sm))
                                    .foregroundStyle(DS.Palette.accentText)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.word + " (约)")
                                        .vkFont(.subheadline, weight: .medium)
                                        .foregroundStyle(DS.Palette.text)
                                    Text("近 30 天约 " + String(c.count) + " 次开门")
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                                Spacer(minLength: 0)
                                Text("#" + String(i + 1))
                                    .vkFont(.caption.monospacedDigit())
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("口径: 近 30 天开门日志按凭证类计次 (台账推断, 标「约」)。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("活跃凭证排序")   // 574 活跃凭证排序
                }
            }
            .navigationTitle("活跃凭证")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
    private static func icon(_ kind: String) -> String {
        switch kind {
        case "fp": return "fingerprint"
        case "pwd": return "number"
        case "temp": return "timer"
        default: return "key"
        }
    }
}

// ---------- 包9/575 越界开门清单 (本地检测, 窗口为台账 from/to, 一律标"约") ----------
struct OutWinSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    let wins = RecordSearch.outOfWindow(macs: DB.keychains().map { $0.mac })
                    if wins.isEmpty {
                        Text("没有越界开门 — 临时码都在窗口内使用 (约)。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    ForEach(wins, id: \.rec.id) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: DS.Space.s) {
                                Text(w.rec.lockName)
                                    .vkFont(.caption2, weight: .medium)
                                    .lineLimit(1)
                                    .foregroundStyle(DS.Palette.accentText)
                                    .padding(.horizontal, DS.Space.s)
                                    .padding(.vertical, 2)
                                    .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                                Text(w.rec.timeStr)
                                    .vkFont(.footnote.monospacedDigit())
                                    .foregroundStyle(DS.Palette.text)
                            }
                            Text("临时码窗口 " + w.window + " 外仍产生开门 — 约越界")   // 575 外仍产生开门
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("越界开门清单 (约)")
                } footer: {
                    Text("口径: 临时码台账生效区间之外仍出现一次性密码开门 (本地检测, 时刻为锁端时间)。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("越界开门")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
        }
    }
}