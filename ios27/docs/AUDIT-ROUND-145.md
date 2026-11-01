# AUDIT-ROUND-145 · 第一百四十五轮：「永久有效」判据被抄了三份

> CI：`6c9d78f` 已验证绿；`1414f20` 待回执。本轮本地提交。

## 1. 起点：`rescheduleAllAlerts` 自己写了一遍"永久"判据

```swift
for p in DB.listPwds(mac) where !p.to.hasPrefix("2118") {   // ← 绕过 expiryDate
```

而**同一个文件上方 150 行**就有唯一口径：

```swift
/// 永久有效期 (2118) 返回 nil — 不参与到期排序与预警
static func expiryDate(_ p: LedgerPwd) -> Date? {
    guard !p.to.hasPrefix("2118") else { return nil }
    return parseLocal(p.to)
}
```

## 2. 全仓 7 处 `hasPrefix("2118")` 的逐个判定

| 位置 | 性质 | 处置 |
|---|---|---|
| `CredentialOrgState:9`（`expiryDate` 本身） | **口径来源** | 保留（它就该是唯一一处） |
| `CredentialOrgState:159`（`rescheduleAllAlerts`） | 抄了一份 | **改用 `expiryDate(p) != nil`** |
| `CredentialStudioParts:32`（展示分支） | 抄了一份 | **改用 `CredentialOrg.expiryDate(pwd) == nil`** |
| `CredentialOrg:548/549`（文案"长期有效"） | 语义独立（拼显示串） | 保留 |
| `MobileKeyService:202` | 手机钥匙域（`k.forever` 之外的兜底） | 保留 |

## 3. 为什么这类"抄判据"值得修

它**不会立刻出错** —— `"2118"` 这个前缀目前在 7 处都一致。
但一旦有人改约定（比如换成 `"9999"` 或改用 `Date` 表示永久），**必须改 7 处**，而漏掉任何一处
都会造成"同一张凭证在预警页是永久、在回收站页是有期限"这类分裂。

本段已在这条判据上修过：

| 轮次 | 缺陷 |
|---|---|
| 133 | `HHMemberStatus` 四态被写成二分支 |
| 143 | 三处诊断缓存只有一处回填 |
| **145** | **"永久"判据抄了三份** |

## 4. 方法论

**"同一个判据在多处各写一遍"是一个可机械发现的形态** —— 但发现方式不是搜函数名，
而是**搜那个判据的常量/字面量**（本例是 `"2118"`）。

| 搜什么 | 能找到 |
|---|---|
| 函数名 | 同名实现 |
| **判据里的字面量** | **所有自己写了一遍判据的地方** |

判据：**一个判据只要有"唯一口径函数"，其它地方就不该出现它的内部字面量。**
（唯一例外是那个口径函数自身。）

## 5. 顺带核对（无缺陷）

`CredentialOrgState` 的通知族三入口（`cancelAlerts` / `cancelAllForDecoy` / `rescheduleAllAlerts`）
都走同一条 `enqueue` 串行链 ✅ —— 这是 ROUND-58 修的 SEC-32 竞态，现在形状正确。
