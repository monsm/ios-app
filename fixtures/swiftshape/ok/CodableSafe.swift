// R3 反控：同样的三个非 Optional 带默认值字段，但**有显式 init(from:)** (全部 decodeIfPresent)
// ⇒ 不在雷区名单里。这正是第一百三十七批给 LockMeta 补的那一类写法。
import Foundation

struct R3Safe: Codable {
    var name: String = ""
    var count: Int = 0
    var on: Bool = false

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
    }
    private enum CodingKeys: String, CodingKey { case name, count, on }
}
