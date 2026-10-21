// ---------- 同屏"闲时提醒"预算 (乱源治理第 2 批) ----------
// 起因: 顶部六条横幅 + 设备页两条教学浮签各自独立 `if`，谁都不知道"这屏已经有别的在说话"——
//       组合起来同屏能同时挂 3~4 条互不相干的指路条，这就是"乱"的最大一坨。
// 口径: 任意时刻只挂 **一条** 闲时提醒; 被压住的那几条不丢，折进顶部一枚汇总胶囊，
//       点开逐条给**它原本就有的动作** (不新造做不到的动作 —— 832 那条教训)。
// 不参赛的四类，因为它们不是"闲时提醒":
//   · 演示模式横幅 344/836: 演示数据必须全程可辨识，让它让位等于撒。
//   · 蓝牙关横幅 69: 主流程被它阻断，藏起来只会让人以为 App 坏了。
//   · toast 与 508 写入回执: 是用户自己刚那个动作的回声，不是提醒。
//   · 377 访客通道入口: 门禁，让位就等于放开受限区。
import SwiftUI

enum Ambient: String, CaseIterable, Identifiable {
    case selfCheck          // 8/448 本机库体自检异常
    case pasteCare          // 344/517 剪贴板粘贴建议 (有时效窗口)
    case firstUseCapsule    // 42/268 首用: 长按胶囊看状态变化
    case quickTileTip       // 827 快捷格逐格揭幕提示

    var id: String { rawValue }

    /// 排位依据: 数据完整性 > 有到期时刻的隐私提示 > 只用一次的首用教学 > 可一直等到用户主动用的逐格教学
    var rank: Int {
        switch self {
        case .selfCheck: return 0
        case .pasteCare: return 1
        case .firstUseCapsule: return 2
        case .quickTileTip: return 3
        }
    }

    var icon: String {
        switch self {
        case .selfCheck: return "exclamationmark.triangle"
        case .pasteCare: return "doc.on.clipboard"
        case .firstUseCapsule: return "hand.point.up.left"
        case .quickTileTip: return "hand.point.up.left"
        }
    }
}

/// 排位这一步单独拆出来: 纯函数, 不碰视图也不碰存储, 便于"同一批候选换了优先级"这种改动可核对
enum NoticeBudget {
    static func ranked(_ present: [Ambient]) -> [Ambient] {
        var out: [Ambient] = []
        for a in present where !out.contains(a) { out.append(a) }   // 去重 + 稳定
        return out.sorted { $0.rank < $1.rank }
    }
}

/// 汇总页: 把被压掉的每一条按"原文案 + 原动作"列出来。
/// 每个按钮都指向本屏本来就做得出的那件事 (requestTab / ClipboardCare / HintOnce)，没有新造落点。
struct AmbientOverflowSheet: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.ambientRest) { a in row(a) }
                } header: {
                    Text("这一屏只留了一条提醒，其余在这里")
                }
                // 口径如实写: 上台的那一条不重复列，免得用户以为有两处"去诊断"
                if let top = app.ambientTop {
                    Section {
                        LabeledRow("正在屏上显示", AmbientCopy.text(top, app: app))
                    } header: {
                        Text("当前这一条")
                    }
                }
            }
            .navigationTitle("\(app.ambientRest.count) 条提醒")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { app.showAmbientList = false }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ a: Ambient) -> some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            HStack(alignment: .top, spacing: XSpace.xs) {
                Image(systemName: a.icon)
                    .font(.system(size: XIcon.sm))
                    .foregroundStyle(XPalette.textSub)
                    .accessibilityHidden(true)
                Text(AmbientCopy.text(a, app: app))
                    .xFont(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: XSpace.s) {
                ForEach(AmbientCopy.actions(a, app: app)) { act in
                    Button(act.title) { act.run() }
                        .xFont(.caption, weight: .medium)
                        .buttonStyle(.bordered)
                        .frame(minHeight: XHit.min - XSpace.m)
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: XHit.min)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, XSpace.xs)
    }
}

/// 每条闲时提醒的文案与动作。从各横幅内联处搬来，语义一字未改 ——
/// 集中在这里是为了"屏上那一条"和"汇总里那一条"说法必须完全一致，不允许两套。
enum AmbientCopy {
    struct Action: Identifiable { let id: String; let title: String; let run: @MainActor () -> Void }

    @MainActor
    static func text(_ a: Ambient, app: AppState) -> String {
        switch a {
        case .selfCheck:
            return BackupStudio.selfCheckWarning ?? "本机库体与上次快照不一致"
        case .pasteCare:
            guard let s = app.pasteSuggestion else { return "剪贴板提醒" }
            switch s.stage {
            case .waiting(let n): return "刚复制的「\(s.label)」还在剪贴板 — \(n) 秒后自动清除"
            case .cleared: return "刚复制的「\(s.label)」到点已自动清除"
            }
        case .firstUseCapsule:
            return "长按主控卡上的「连接耗时」标记可看最近状态变化"
        case .quickTileTip:
            guard let t = app.quickTipTile else { return "快捷格提示" }
            return "试试「" + t.label + "」—— 这一格你还没用过"
        }
    }

    @MainActor
    static func actions(_ a: Ambient, app: AppState) -> [Action] {
        switch a {
        case .selfCheck:
            // 2026-10-15 走查 §4.3: 按钮写的是"去诊断", 原来只 requestTab(3) 把人放在设置页根上,
            // 而「诊断与运行日志」是那一页里的一行 —— 切过去不等于送到。带上落点名, 由设置页开诊断面。
            return [Action(id: "diag", title: "去诊断") {
                app.pendingSettingsFocus = "diag"
                app.requestRoute(.settings)
            }]   // 377: 走 requestTab 那道访客门禁
        case .pasteCare:
            if let s = app.pasteSuggestion, case .waiting = s.stage {
                return [
                    Action(id: "clear", title: "立即清除") {   // 517: 唯一出口是 clearNow()，不直接写 pasteboard
                        ClipboardCare.clearNow()
                        withAnimation(XMotion.standard) { app.pasteSuggestion = nil }
                    },
                    Action(id: "ok", title: "知道了") {
                        ClipboardCare.dismissSuggestion()
                        withAnimation(XMotion.standard) { app.pasteSuggestion = nil }
                    },
                ]
            }
            return [
                Action(id: "cred", title: "回凭证页") {
                    ClipboardCare.dismissSuggestion()
                    app.requestRoute(.credentials)
                    withAnimation(XMotion.standard) { app.pasteSuggestion = nil }
                },
                Action(id: "ok", title: "知道了") {
                    ClipboardCare.dismissSuggestion()
                    withAnimation(XMotion.standard) { app.pasteSuggestion = nil }
                },
            ]
        case .firstUseCapsule:
            // 两份都写: 盘上是"下次启动还认"，firstUseCapsuleDone 是即时态 —— 只 mark 的话这一条会留在汇总页里不走
            return [Action(id: "got", title: "知道了") {
                app.firstUseCapsuleDone = true
                HintOnce.mark("capsule268")
            }]
        case .quickTileTip:
            // 只给"不再提示"这一件屏上真做得出的事; "点那一格"是设备页上的动作，这里不替用户点。
            // 两份都要写: HintOnce 落盘 (下次启动还认), ambientTipOff 是即时态 (按钮按下就得看见生效)
            return [
                Action(id: "off", title: "不再提示") {
                    app.ambientTipOff = true
                    HintOnce.mark("827off")
                },
                Action(id: "go", title: "去设备页") { app.requestRoute(.device) },
            ]
        }
    }
}
