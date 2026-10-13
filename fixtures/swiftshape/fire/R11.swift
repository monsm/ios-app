// R11 正控: `as:` 后跟编码类型缺 `.self` ⇒ 该响。
// 编译器报 "expected member name or initializer call after type name"。
import Foundation

enum R11Fire {
    static func decode(_ d: Data) -> String {
        return String(decoding: d, as: UTF8)
    }
}
