// 记录 Tab (records 页) — 门锁日志 (cmd16 翻页) + 成员过滤 + 归属推断 + 离线缓存
// 离线横幅只在"确实没有一次成功的实时读取"时出现, 不再每次进页都误报未连接。
// 包9 增量: 时间线升级 (578 组头吸顶 / 738 告警行红条+浅红底 / 592 连击合并 /
//           183 成员色点 / 184 开门方式图标 / 655 动词化文案 / 681 农历小字 /
//           679 年份分隔 / 649 凌晨归属 / 590 连续活跃 / 796 第N位使用者 /
//           1016 出行观察 / 785 泳道时间线) +
//           检索 (551/553/554/555/557/562/560/564/571/572/567/568/569/570/574/575/561/770) +
//           告警中心入口 (735 未处置角标) + 详情 (576/577/727/736/737/742, 见 RecordsTimeline.swift)。
// 本批 (第一百八十九批·记录族默认路径):
//   · 576/583/585/586 在「当前锁」视图打通 —— Rec 池原先只在「全部锁」分支赋值, 默认路径恒空,
//     点时间线行永远打不开详情; 行身份从此只经一份算术 (RecordOverlay.oid, RecordSearch.swift:21)。
//   · 582 统计页成员条下钻补上消费点 (pendingRecordsMember 原先全仓零读取方)。
//   · 551 搜索面补进 186 备注与 568 凭证标签, 与搜索框占位文案的承诺对齐。
//   · 593 组尾「全天 N 条」改成**过滤与分页截断之前**的行池口径。
//   · 808 记录空态按原句铺 3 条灰阶示例条目 + 点按弹「真实数据从这里开始」引导卡。
// 纪律: 颜色只经 DS 令牌; 归属类统计一律标"约"; 告警类型只用真实 5 种 (6/7/10/13/224)。
import SwiftUI
import UIKit


// ---------- 565 告警类型多选面板 ----------
/// 对勾列表按库里**实际**告警类型渲染 (StatsKit.alarmTypes 五类)。原句列了"胁迫", 但协议日志
/// 类型表没有胁迫类 (与 725 判 ❌ 同一理由) —— 不虚构一个查不到的类型, 也在面板里把这件事写明。
/// 选中集直接绑定 filters.alarmKinds (空 = 不限类型; 选中数回显在打开的 chip 上)。
struct AlarmKindsSheet: View {
    @Binding var sel: Set<Int>
    @Environment(\.dismiss) private var dismiss
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

// ---------- 包9/575 越界开门清单 (本地检测, 窗口为台账 from/to, 一律标"约") ----------

// ---------- 1045 感谢清单 (本地按月留存, 可生成感谢卡文本) ----------

