// R3 正控：持久化 struct 靠合成 Codable，却带着"非 Optional + 有默认值"的字段，
// 而且**没有**显式 init(from:) ⇒ 这个 struct 必须被数进雷区名单。
// 这份文件不在任何 target 的 sources 里 (project.yml 只收 App/Widget/Tests)，
// 它存在的唯一意义是让判据可以被证伪 —— 数不出它，R3 就只是一句注释。
import Foundation

struct R3Risky: Codable {
    var name: String = ""
    var count: Int = 0
    var on: Bool = false
}

/// 第二份正控：**整行写完**的小 struct。R3 的第一版看不见这种写法 (逐行收 body 时
/// 这一行的左右括号互相抵消，`j>i` 的分支永远收不到字段)，是当场注入探针才发现的。
/// 留着这一份，判据以后再也不能"看不见单行写法"。
struct R3RiskyOneLine: Codable { var z: Int = 0 }
