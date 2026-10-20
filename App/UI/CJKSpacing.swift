import SwiftUI
import Foundation

// 668 中西文间距 (排版实现) —— 2026-10-20: 从被删除的 HelpCenter.swift 中独立出来。
// 这三个是**通用排版工具** (LabeledRow 等短标签在用), 不是帮助中心专属, 必须保留。

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
