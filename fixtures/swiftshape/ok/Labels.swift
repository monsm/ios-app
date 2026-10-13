// R4 反控：写对的标签 + 三类"判不了就不报"的形状，一条都不许响。
// 这文件的意义和 fire/R4.swift 一样是证伪：如果这里响了，说明判据把 Apple 同名成员
// 或带默认值的声明也算进来了 —— 那正是上一版无差别探针 210 条里 200 条噪音的成因。
import Foundation

enum Safe {
    static func oid(mac: String, rowKey: String) -> String { mac + "#" + rowKey }
    // 第二参带默认值 ⇒ 那一参判不了，但首参仍然判得了 —— 这条不该响
    static func load(_ path: String, as kind: String = "json") -> String { path + kind }
    func legendRow(labels: [String]) -> String { labels.joined() }
    // 参数表里有闭包类型 ⇒ 判不了 (豁免 2)
    static func run(body: () -> Void) { body() }
}

struct OkLabels {
    let items: [String]
    var merged: String {
        let a = Safe.oid(mac: "AA", rowKey: "1")        // 标签写全
        let b = Safe.load("p", as: "json")              // 首参本来就是无外部标签
        let c = legendRow(labels: items)                // 声明是 labels:，调用也是
        let d = "oid(x)".count                          // 字符串里的假调用不算调用点
        return a + b + c + String(d)
    }
    private func legendRow(labels: [String]) -> String { labels.join(separator: ",") }
}

// Apple 同名成员：前面带 "."，本判据不收 (豁免 1)。写成 `arr.remove(at: 0)` 那种实例调用同理。
func appleNoise(_ s: String, arr: [Int]) -> String {
    let r = arr.remove(at: 0)
    return s.trimmingCharacters(in: .whitespaces) + String(r)
}
