// R1/R2 的反控：四种"看起来像但其实合法"的形状，一个都不许响。
// 响了的闸门就会开始制造噪音，而噪音的闸门没人看 (本仓 apisweep 头注里写着这条教训)。
import SwiftUI

struct OkBodyNoBuilder: View {
    // `var body` 由 View 协议自带 @ViewBuilder，实现处不写也合法 ⇒ R1 必须放过
    var body: some View {
        VStack {
            if flag {
                Text("开")
            }
        }
    }
    var flag = false
}

struct OkAttributedAfterComment: View {
    // 属性在 /// 文档注释之前，但它落的下一个声明确实是 some View ⇒ 合法
    private var title: some View {
        Text("标题")
    }

    @ViewBuilder
    /// 一段说明
    private var cards: some View {
        if flag {
            Text("有")
        }
    }
    var flag = false
}

struct OkReturnPath: View {
    // 有显式 return 的成员不需要 builder
    private var maybe: some View {
        if flag {
            return Text("开")
        }
        return Text("关")
    }
    var flag = false
}

struct OkElsePath: View {
    // 有 else 的顶层 if 是二选一，同样不需要 builder 兜住"空分支"
    private var either: some View {
        if flag {
            Text("开")
        } else {
            Text("关")
        }
    }
    var flag = false
}

struct OkUntypedFunc: View {
    // 判不了/不该响：@ViewBuilder 函数但**从未被当 View 调用** (没有调用点) ⇒ R6 不响。
    // 注: 这只说明"没有调用点就不报", 不代表该形状一定编得过 —— 见 R6 头注里两轮 run 的取舍。
    @ViewBuilder
    private func untypedRow(_ t: String) {
        Text(t)
    }
}

struct OkLetWithReturn: View {
    // R1b 反控之一：body 以 let 起头，但有**显式 return** ⇒ 多语句 body 不需要结果构建器 ⇒ 不报。
    // 本仓大量存在这种写法 (AchievementsView/weekGoal、CredentialsView/segChip …)，误报就是噪音。
    var n: Int
    private var card: some View {
        let title = "共 \(n) 条"
        let tone = n > 0 ? "满" : "空"
        return Text(title + " · " + tone)
    }
}

struct OkLetWithBuilder: View {
    // R1b 反控之二：body 以 let 起头，但写了 @ViewBuilder ⇒ 合法 (rhythmSection 修好后的形状) ⇒ 不报。
    var n: Int
    @ViewBuilder
    private var card: some View {
        let title = "共 \(n) 条"
        let tone = n > 0 ? "满" : "空"
        Section("单据") {
            Text(title + " · " + tone)
        }
    }
}

struct OkLetSameLine: View {
    // R1b 反控之三：整行写完的 body (`private var x: some View { Text(…) }`) 里没有顶层语句 ⇒ 不报。
    var n: Int
    private var badge: some View { Text("\(n)") }
}

struct OkViewFuncWithArrow: View {
    // R6 反控之一：视图函数**写了** `-> some View` ⇒ 合法 (rhythmSection/StatsView 修好后的形状) ⇒ 不报。
    var show: Bool
    var body: some View {
        Section("容器") {
            card()
        }
    }
    @ViewBuilder
    private func card() -> some View {
        let n = 1
        Section("详情") { Text("条数 \(n)") }
    }
}

struct OkVoidActionFunc: View {
    // R6 反控之二：真正的动作函数 (写留痕 + 刷新), 返回 Void 是**本意**, 体内也没有视图构造 ⇒ 不报。
    // 本仓 AlarmCenterView/markDone 就是这个形状, 报它就是噪音。
    var tick = 0
    var body: some View {
        Button("已处理") { markDone("k") }
    }
    private func markDone(_ key: String) {
        _ = key
        tick += 1
    }
}

struct OkVoidFuncNoViewCtor: View {
    // R6 反控之三：无返回类型、但体内**没有任何视图构造** (纯计算) ⇒ 即使被当语句调用也不报。
    var n: Int
    var body: some View {
        Text("\(compute())")
    }
    private func compute() {
        _ = n
    }
}

struct OkBuilderParam: View {
    // R7 反控：@ViewBuilder 参数属性 (同一行/缩进更深) 不是"重复挂属性" ⇒ 不报。
    // 本仓 SettingsView/newBadgeRow 就是这个形状。
    var body: some View {
        labeledRow("标题") { Text("内容") }
    }
    @ViewBuilder
    func labeledRow(_ title: String, @ViewBuilder dest: () -> some View) -> some View {
        dest()
    }
}

// (已移除 OkBuilderNoArrow 反控)
// 该 fixture 曾断言"带 @ViewBuilder 但无 -> some View 的函数可被当 View 用"。
// 但这一断言本机无编译器, 从未被证实; run 58 的 CI 又只报了重复 @ViewBuilder, 未证伪也未证实。
// 按 R6 头部注释的取舍: 既然真身证据不足, 就不留"当作合法"的反控, 一律要求写 -> some View。

// ---- R8/R9 反控: 带 footer 的 Section 只能用三段式; isExpanded 重载干脆不带 footer ----
struct OkSectionForms: View {
    @State private var open = true
    var body: some View {
        Form {
            // 三段式: 合法 (本仓修完 run 59 后的统一写法)
            Section {
                Text("操作流水")
            } header: {
                Text("操作流水 (156)")
            } footer: {
                Text("只留最近若干条。")
            }
            // isExpanded 重载带 header 不带 footer: 合法
            Section(isExpanded: $open) {
                Text("一组锁")
            } header: {
                Text("未分组")
            }
        }
    }
}

// ---- R10 反控: maxWidth 写在 minHeight 之前是合法次序 ----
struct OkFrameOrder: View {
    var body: some View {
        Button("重来一遍") { }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

// ---- R11 反控: as: 后写元类型 (带 .self) 是合法写法 ----
enum OkMetaType {
    static func decode(_ d: Data) -> String {
        return String(decoding: d, as: UTF8.self)
    }
}

// ---- R12 反控: View 扩展方法对 self 调修饰符 (隐式 self) 或显式写 self, 都合法 ----
extension View {
    func okScreenBackground() -> some View {
        background { Color.clear.ignoresSafeArea() }          // 隐式 self 的修饰符调用
    }
    @ViewBuilder
    func okOnehand(_ on: Bool) -> some View {
        if on { offset(y: 48) } else { self }                 // 显式 self
    }
}

