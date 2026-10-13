// S2 正控: 带标签的尾随闭包后接非闭包表达式 (RecordsView:841/845/849 同形)
struct S2Boom: View {
    var body: some View {
        VStack {
            chipRow("时段", selected: 0) { name, i in
                _ = name
                _ = i
            } items: [("全部", 0), ("早晨", 1)]
            f(a: {
                tick()
            } b: 2)
        }
    }
}
