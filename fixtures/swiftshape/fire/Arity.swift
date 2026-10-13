// R5 正控：实参**个数**与声明对不上。声明里既没有默认值也没有闭包参数 ⇒ 个数是定死的，
// 少一个 (`missing argument`) 或多一个 (`extra argument in call`) 都是编译器必拒。
// 现网扫描把调用点从"按行截"改成"按整份文本取配平括号"之后，才把这一类接进同一套流水。
enum Count {
    static func three(_ a: Int, _ b: Int, _ c: Int) -> Int { a + b + c }
    static func one(_ a: Int) -> Int { a }
}

func useCount() -> Int {
    let x = Count.three(1, 2)
    let y = Count.one(1, 2)
    return x + y
}
