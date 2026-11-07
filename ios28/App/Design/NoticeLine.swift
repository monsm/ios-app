// NoticeLine.swift —— 页内提示行的**唯一**写法。
//
// 之前同一件事在 16 个页面里有 16 种画法（红字/灰字/黄铜字、有的带图标有的不带、
// padding 从 8 到 14 都有）。现在只有这一种：
//   · error  → 朱红 + 感叹号（动作失败，页内就地可见）
//   · ok     → 黄铜 + 对勾（动作成功的一句话回执）
//   · info   → 灰 + i（不需要行动的说明）
import SwiftUI

struct NoticeLine: View {
    enum Tone { case error, ok, info }

    var text: String
    var tone: Tone = .error

    private var icon: String {
        switch tone {
        case .error: return "exclamationmark.circle"
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        }
    }

    private var tint: Color {
        switch tone {
        case .error: return T.C.danger
        case .ok: return T.C.brass
        case .info: return T.C.ink3
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
