// R5 反控：两种"括号里的个数比声明少"的合法写法，一条都不许响。
//  ① 尾随闭包：`run(3) { _ in }` 括号里只有 1 个实参，另一个写在括号外 —— 判个数就是误判，
//     所以声明里带闭包类型参数的整个不参与 R5。
//  ② 带默认值的参数可以整个不传：`opt(1)` 合法 ⇒ 声明里任何一位带默认值就不参与 R5。
// 这两种在 R4 (逐位判标签) 里是"从该位起停"，在 R5 里是"整条不判"—— 判据比标签更严。
import Foundation

enum SafeCount {
    static func run(_ n: Int, body: (Int) -> Void) { body(n) }
    static func opt(_ a: Int, b: Int = 2) -> Int { a + b }
    static func two(_ a: Int, _ b: Int) -> Int { a + b }
}

func okArity() -> Int {
    var hit = 0
    SafeCount.run(3) { _ in }
    let z = SafeCount.opt(1)
    let w = SafeCount.two(1, 2)
    hit = z + w
    return hit
}
