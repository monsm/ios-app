// S1 正控: for-in 头部的顶层逗号 (AuditChain:448 / CredentialOrg:806 / DiagKit:238 同形)
func s1(_ mac: String, xs: [Int], ys: [Int]) {
    var hits: [String] = []
    for p in DB.listPwds(mac) where p.alias != "x", p.pwd == "y" {
        hits.append(p.alias)
    }
    for p in DB.listPwds(mac) where p.temp && !archived(mac), let o = p.owner, !o.isEmpty {
        hits.append(o)
    }
    for x in xs, ys where x > 0 {
        hits.append("\(x)")
    }
}
