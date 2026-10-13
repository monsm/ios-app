// 927 桌面/锁屏小组件 —— **哑按钮**（拍板 #30 选 B，不选"在小组件里开锁"）
//
// 为什么只能是哑按钮：docs/CONSTRAINTS.md 明确列出免费账号 (Personal Team) **不可用 App Groups**，
// 所以本扩展读不到主 App 的任何数据 —— 没有 SQLite、没有偏好、没有钥匙串。
// 于是小组件里出现的一切文字都只能是"与锁无关的常量"：
//   · 不得显示锁状态/电量/最近开门（那需要 App Groups，属 924 已判 ❌ 的那条路）；
//   · 不得写成"在锁屏开锁"——它只做一件事：把主 App 打到设备页（tab 0，开锁圆盘就在那页）。
// 933「渲染跟随」在这里的落点也只是**语义色**：组件跟随系统浅色/深色，
// 不跟随 App 内主题（主题存在 kf_theme，跨不过 target 边界）。
// 887「哑 Widget 染色资产」在此的形态：组件零图片资产（全 SF Symbol + 系统语义色），
// 系统在彩色/单色(tinted)/透明各渲染模式下自行染色，无需图资产变体。
//
// 本文件**不能** import 主 App 的任何类型：app-extension 是独立编译单元，
// DesignSystem/DB/LockService 都不在这个 target 的源码里。刻意保持零依赖。
// 例外只有一个: `Shared/LiveUnlockActivity.swift` —— 那份源码被 project.yml 同时挂进两个 target,
// 所以 `UnlockActivityAttributes` 在两边是同一个形状 (ActivityKit 要求属性类型跨 target 一致)。
import SwiftUI
import WidgetKit

/// 时间线条目：只有一个常量字段。留这个结构而不是直接用 EmptyEntry，
/// 是为了让"以后若真拿到 App Groups 要显示状态"时有个明确的落点，而不是到时候重写整条链。
struct DialEntry: TimelineEntry {
    let date: Date
}

struct DialProvider: TimelineProvider {
    func placeholder(in context: Context) -> DialEntry { DialEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (DialEntry) -> Void) {
        completion(DialEntry(date: Date()))
    }

    // 一次刷新都不需要：内容不含会变的数据。策略给 .after(+) 而不是 .never()，
    // 因为 .after 让系统按自己的节奏回收快照；这里没有任何"到某时刻会变"的事实可承诺。
    func getTimeline(in context: Context, completion: @escaping (Timeline<DialEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [DialEntry(date: now)], policy: .after(now.addingTimeInterval(86_400))))
    }
}

struct DialWidgetView: View {
    var entry: DialEntry
    @Environment(\.widgetFamily) private var family

    // 深链落点：白名单里的 "device" = 主 App tab 0 (DeviceHomeView，开锁圆盘在该页)。
    // 主 App 侧 handleDeepLink 在应用锁未解开时把路由挂起 (LockKeeperApp.swift:61-70)，
    // 所以这条链接**不构成绕过**：没解锁就只会停在解锁页。
    private static let target = URL(string: "kf://device")!

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(spacing: 6) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 26, weight: .medium))
                    Text("开锁")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(.tint)
                .accessibilityLabel("离线锁管家：打开 App 到设备页开锁")
                .widgetURL(Self.target)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open")
                            .font(.system(size: 18, weight: .medium))
                        Text("到设备页开锁")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                    }
                    // 这句是**给用户看的边界声明**，不是装饰：不写清"这里不开锁"，
                    // 用户会以为点一下就能开门，然后怪组件失灵。
                    Text("本组件不执行开锁 · 开锁在 App 内完成（需应用锁与蓝牙）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Link("打开离线锁管家", destination: Self.target)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("离线锁管家：打开 App 到设备页。本组件不执行开锁。")
            }
        }
        // 只用系统语义色 → 933 的"渲染跟随"落在系统浅色/深色上；App 内主题跨不过 target 边界 (无 App Groups)。
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ---------- 77 / 939 / 941 开锁实时活动 (灵动岛 + 锁屏) ----------
/// 主 App 侧由 `LiveUnlock` 起活动并更新阶段; 这里只负责呈现。
/// 动态岛三处 (展开/紧凑/最小) 都写全: 缺 compactTrailing 时紧凑态会只剩一个图标, 读不出阶段。
/// 数据全部来自活动属性与 ContentState —— 组件**不读本机台账** (免费 Team 无 App Groups, 与 927 同一条约束)。
struct UnlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UnlockActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: context.state.phase.symbol)
                    .font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.lockName)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text(context.state.phase.label)
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(context.attributes.lockName) \(context.state.phase.label)")
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.phase.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.lockName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase.label)
                        .font(.caption)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.phase == .unlocked ? "本次开门已记录 (77)" : "正在与门锁握手")
                        .font(.caption2)
                        .opacity(0.8)
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbol)
                    .font(.system(size: 14))
            } compactTrailing: {
                Text(context.state.phase == .unlocked ? "已开" : (context.state.phase == .failed ? "失败" : "连接"))
                    .font(.caption2)
            } minimal: {
                Image(systemName: context.state.phase.symbol)
                    .font(.system(size: 14))
            }
            .keylineTint(.accentColor)
        }
    }
}

struct DialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialWidget", provider: DialProvider()) { entry in
            DialWidgetView(entry: entry)
        }
        .configurationDisplayName("开锁入口")
        .description("点按打开 App 到设备页。本组件不含锁状态、电量，也不执行开锁。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct OfflineLockWidgetBundle: WidgetBundle {
    var body: some Widget {
        DialWidget()
        UnlockLiveActivity()   // 77/939/941
    }
}
