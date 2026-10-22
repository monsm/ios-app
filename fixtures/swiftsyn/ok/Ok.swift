// ok 反控: 四类判据的合法近亲写法, 一条都不许响
struct OkSyn: View {
    @State private var n = 0
    @State private var price = 0
    let items = [1, 2, 3]
    let pairs = [(1, 2), (3, 4)]
    let v = 1

    var body: some View {
        VStack {
            Button {
                n += 1
            } label: {
                Label("\(n) 次", systemImage: "plus")
            }
            Text("合计 $100, 含 \(items.count) 条")
            Text("价格 $ \(price) 元")
            if n > 0 {
                tick()
            } else {
                tock()
            }
        }
    }

    func s1ok(_ xs: [Int]) {
        var hits: [Int] = []
        for x in xs.filter { $0 > 1 } { hits.append(x) }
        for x in xs where x > 0 { hits.append(x) }
        for x in xs where f(x, x + 1) { hits.append(x) }
        for (a, b) in pairs { hits.append(a + b) }
        for _ in xs { hits.append(0) }
        if let a = xs.first, a > 0 { hits.append(a) }
        guard let a = xs.first, a > 1 else { return }
        hits.append(xs.reduce(0) { $0 + $1 })
    }

    func s2ok() {
        f(a: {
            tick()
        }, b: 2)
        switch v {
        case 1:
            run {
                tick()
            }
        default:
            break
        }
        let d = [Self.self: 1, items: 2]
        _ = d
    }

    func s4ok(_ cb: @Sendable @escaping () -> Void) { cb() }

    func s4ok2(_ cb:
        @escaping () -> Void) { cb() }
}

let ml = """
// 交接信里有 $ 与 \(count) 和逗号, 都在字符串里
"""

// S5 反控：合法的中文收尾，不该开火。
func s5Ok() -> String {
    let a = "全部同数字, 易被猜出"
    let b = a + "，请换一个"
    return b.count > 0 ? "已保存" : "未保存"
}
