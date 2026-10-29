// 记录行 · 辅助（成员色 / 记录查找 / 高亮分段 / 日期）
// 2026-10-29 从 RecordsRows.swift（834 行）拆出。
import SwiftUI

extension RecordsRows {
    func highlightSegments(_ text: String) -> [HlSeg] {
        guard !highlightTokens.isEmpty else { return [HlSeg(text: text, hit: false, id: 0)] }
        var segs = [HlSeg]()
        var rest = Substring(text)
        var idx = 0
        while !rest.isEmpty {
            var bestOff = -1
            var bestTok = ""
            for tok in highlightTokens where tok.count >= 1 {
                if let rng = rest.range(of: tok, options: .caseInsensitive) {
                    let off = rest.distance(from: rest.startIndex, to: rng.lowerBound)
                    if bestOff < 0 || off < bestOff {
                        bestOff = off
                        bestTok = tok
                    }
                }
            }
            if bestOff < 0 {
                segs.append(HlSeg(text: String(rest), hit: false, id: idx)); idx += 1
                break
            }
            let pre = String(rest.prefix(bestOff))
            let hitTxt = String(rest.dropFirst(bestOff).prefix(bestTok.count))
            if !pre.isEmpty {
                segs.append(HlSeg(text: pre, hit: false, id: idx)); idx += 1
            }
            segs.append(HlSeg(text: hitTxt, hit: true, id: idx)); idx += 1
            rest = rest.dropFirst(bestOff + hitTxt.count)
        }
        return segs
    }
    func memberColor(_ m: Member) -> Color {
        var s = m.color
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16)
        return v.map { Color(hex: $0) } ?? DS.Palette.accent
    }
    /// 576 行 → Rec: 单锁与全部锁**同一条判据**, 键的算术只有 `RecordOverlay.oid` 一份
    /// (行侧就是 `RowVM.id` 那一个 oid, Rec 侧在这里现算, 不再各自拼 "mac#key")。
    /// 旧写法先问 `$0.id == r.key`: Rec.id 恒带 mac 前缀, 而单锁路径的 r.key 不带 ⇒ 那一问永远不中;
    /// 第二问又只有在 recPool 非空时才可能命中, 而 recPool 原先只在 scope == 1 分支赋值
    /// ⇒ 默认「当前锁」视图里点行恒得 nil, 576/583/585/586 整条断供。
    func lookupRec(_ r: RowVM) -> Rec? {
        recPool.first { RecordOverlay.oid(mac: $0.mac, rowKey: $0.key) == r.id }
    }
}
