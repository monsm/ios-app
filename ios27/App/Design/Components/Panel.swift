// Panel.swift —— 内容层的唯一容器语法。
//
// 纪律：内容层永远不透明、永远不用玻璃、永远只有一级阴影（≤0.06）。
// 面板靠「0.5pt 蚀刻描边 + plate/paper 明度差」分层，不靠投影。
import SwiftUI

/// 内容面板。同心圆角：外 20 → 内 16 → 控件 12。
struct Panel<Content: View>: View {
    var inset: CGFloat = T.S.l
    var radius: CGFloat = T.R.plate
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.plate, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
            }
    }
}

/// 凹槽块：放在 Panel 内部的次级分组（刻度底、读数条、内嵌列表）。
struct Inset<Content: View>: View {
    var inset: CGFloat = T.S.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.plateAlt, in: .rect(cornerRadius: T.R.inset))
    }
}

/// 小节标题。中文不加 tracking（方块字等宽）；只有全大写拉丁才加。
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
            Text(text)
                .font(T.F.section)
                .foregroundStyle(Ink.inkSub)
            Spacer(minLength: T.S.s)
            if let trailing {
                Text(trailing)
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 页面底。所有页面统一用这个，保证底色不散。
///
/// 这里 `ignoresSafeArea` 是**有意的、也是唯一允许的**：页面底色必须铺到屏幕四边，
/// 否则刘海与 Home 指示条周围会露出一条系统底色，形成"内嵌窗口"的错觉。
/// 内容层不忽略安全区 —— 它们都在 ScrollView 里，由系统自动避让。
struct CanvasBackground: View {
    var body: some View {
        Ink.paper.ignoresSafeArea(.container, edges: .all)
    }
}
