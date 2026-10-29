// 小管家形象 (841) + 成员中心「给家人开门禁」四步图文的数据源。
//
// 本文件原为 HelpCenter.swift (帮助与文案规范, 673 行): 使用手册整本 / 离线 FAQ /
// 症状排查 / 就任证书 / 演练场 / 文案体检彩蛋。这些页面已随大删波 3 移除 (用户决策:
// 「没锁交互的不影响核心功能的就剥离删掉」)。留下的两件都有真实消费方, 不是文档:
//   · （原计划里的 DemoMascot / EmptyMascotHeader 空态图形**从未实现**，2026-10-26 核实全仓无定义。
//      此处原先指向 DesignSystem:1074，那里也没有。空态图形现由 GuidedEmptyView 承担。）
// 2026-10-27 审核修复 (AUDIT-B 2.8 #8)：这里原有一段「数据来源」清单，
// 其中 `ManualKit.chapters` 已删（全仓 0 命中），`MemberCenterView` 的「四步图文」也已移除。
// 保留那段会让读者去找一个不存在的章节数据源。现在 Mascot 只用本地内置文案。
//     所以这张表只剩一章: 帮助手册整本删了, 但成员页仍在用它, 删表就等于删成员页的教程。
import SwiftUI
import UIKit





// ---------- 881 字幕式过程条: 连接/开锁 验证/执行/完成 三步文字字幕 ----------
// 原住在 AccessibilityView.swift, 该页随大删波 3 移除; 但 DeviceHomeView:1226 仍在用它给听障用户
// 逐字跟读「现在进行到哪一步」, 所以搬到这里作为存活的小构件。
struct CaptionStepBar: View {
    var phase: Int
    var unlockState: AppState.UnlockState

    var body: some View {
        // 非过程态不显示, 听障用户可逐字跟读"现在进行到哪一步"
        if unlockState == .connecting || unlockState == .opening || unlockState == .success {
            captionRow
        }
    }
    private var captionRow: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<3, id: \.self) { i in
                captionStep(i)
            }
        }
        .vkFont(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(captionText)
    }
    @ViewBuilder
    private func captionStep(_ i: Int) -> some View {
        let done = (phase > i + 1) || unlockState == .success
        let active = phase == i + 1 && !done
        HStack(spacing: DS.Space.xs) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "ellipsis.circle" : "circle"))
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            Text(captionName(i))
                .lineLimit(1)
        }
        .foregroundStyle(done ? DS.Palette.ok : (active ? DS.Palette.accentText : DS.Palette.textSub))
        .opacity(done || active ? 1 : 0.55)
        .accessibilityHidden(true)   // 组合朗读已含全部三步, 单步不重复
    }
    private func captionName(_ i: Int) -> String { ["验证", "执行", "完成"][i] }
    private var captionText: String {
        let done = phase > 0 ? "验证" : ""
        return "过程字幕： " + done + (phase > 1 ? " 执行， " : "") + (unlockState == .success ? " 完成" : (phase > 1 ? "执行中" : "进行中"))
    }
}

// ---------- 668 中西文间距 (排版 kerning 路线, 不插不可见字符) ----------
// 原住 HelpCenter.swift (帮助页已随大删波 3 移除), 但 DeviceHomeView:2350/2352 的标签行仍在用,
// 所以与 CaptionStepBar 一起作为存活的小构件留在这里。

// 668 中西文间距 —— 改走排版 (kerning) 路线。
// 原先此处是 `func cjkSpacing() -> some View { return self }`：名字承诺"包一层即补间距"，实现原样返回，
// 谁调都是假生效（全库零调用），已删。同文件的 `String.spaced` 走的是**插 U+2005 字符**的路子，
// 且只有一个调用点：插入不可见字符会让复制、导出、搜索命中都拿到脏文本（拿数据换观感），一并换掉。
private func isCJK668(_ c: Character) -> Bool {
    guard let v = c.unicodeScalars.first?.value else { return false }
    let u = UInt32(v)
    return (0x3000...0x303F).contains(u) || (0x3400...0x4DBF).contains(u)
        || (0x4E00...0x9FFF).contains(u) || (0xF900...0xFAFF).contains(u) || (0xFF00...0xFF60).contains(u)
}
private func isLatin668(_ c: Character) -> Bool {
    (c.isLetter && !isCJK668(c)) || c.isNumber
}

/// 汉字与紧邻拉丁/数字之间加字距：只在边界字符上加 kerning，段内不跟着被拉开，且不插入任何字符。
/// 用于以"中文 + 英文缩写/数字"混排为主的短标签（LabeledRow 一类）；长段落不必用（成本按字符数线性增长）。
func cjkSpaced(_ s: String, gap: CGFloat = 0.09) -> Text {
    let chars = Array(s)
    var hasBoundary = false
    if chars.count > 1 {
        for i in 0..<(chars.count - 1) {
            let a = chars[i], b = chars[i + 1]
            if (isCJK668(a) && isLatin668(b)) || (isLatin668(a) && isCJK668(b)) { hasBoundary = true; break }
        }
    }
    guard hasBoundary else { return Text(s) }        // 纯中文/纯拉丁 → 零成本快路
    // Text + Text 自 iOS 26 弃用。这里的形状 (逐字给不同 kern) 插值表达不了,
    // 所以换成 AttributedString + SwiftUI 的 kern 属性 (attribute-scopes/swiftuiattributes 里在册)。
    // 不设 .font: 字号仍由调用点外面的 .vkFont 决定, 与原先逐段 .kerning 的层级一致。
    var out = AttributedString()
    for i in chars.indices {
        let c = chars[i]
        var k: CGFloat = 0
        if i + 1 < chars.count {
            let b = chars[i + 1]
            if (isCJK668(c) && isLatin668(b)) || (isLatin668(c) && isCJK668(b)) { k = gap }
        }
        var seg = AttributedString(String(c))
        if k != 0 { seg.kern = k }
        out.append(seg)
    }
    return Text(out)
}


// ---------- 长任务期间不许自动锁屏 ----------
// 原住 ScreenCare.swift (录屏遮罩), 那个文件已随本轮删减移除;
// 但 Sheets 的录指纹入口仍在用它 —— 用户手指按在锁上时屏一黑本进程就被挂起, 蓝牙录入链断在半途。
struct ScreenAwakeWhile: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.onChange(of: active, initial: true) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    /// 长任务期间不许自动锁屏。调用点: StartAddFpView (录入中)。
    func keepingScreenAwake(_ active: Bool) -> some View {
        modifier(ScreenAwakeWhile(active: active))
    }
}
