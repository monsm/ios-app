// 一次性提示的共用打点 (42 首用气泡引导族)。
//
// 为什么每条一个键而不是一个"看过引导"总开关: 总开关会让"看过这一条"变成"永远看不到别条" ——
// 用户第一次没注意就再也等不到第二次，而每一条提示讲的是不同的动作。
// 也刻意**不自动计时消失**: 气泡该由用户自己关掉。让它自己飘走，等于用户还没读就被判定"已看过"。
nonisolated enum HintOnce {
    static func shown(_ id: String) -> Bool { DB.store.getBool("kf_hint_" + id) }
    static func mark(_ id: String) { DB.store.set("kf_hint_" + id, true) }
    /// 核弹销毁按 keys() 全表清 (AuditChain)，`kf_hint_*` 前缀天然在内 ——
    /// 这里刻意不提供单独的 clear: 一个"抹掉看过记录"的按钮会被当成"重置教程"的入口，
    /// 而那不需要销毁级权限就能碰。
}
