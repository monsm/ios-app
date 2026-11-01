# AUDIT-ROUND-156 · 第一百五十六轮：按「删实体 → 查引用表」扫了三条路径，全部正确

> CI：`4fd7b89` 已验证绿；`f81185d` / `3eb61f4` 待回执。本轮本地提交。

## 1. 三条删除路径逐个核对

| 函数 | 删什么 | 还有谁引用 | 结论 |
|---|---|---|---|
| `Store.removeDongle` | `kf_keychain_dongles` 里的条目 | **无其它表引用 `dongle.mac`** | ✅ |
| `Store.removeGateway` | `kf_gateways` 里的条目 | **无其它表引用 `gateway.mac`** | ✅ |
| `MobileKeyService.revoke` | 锁端 pin + 本地条目 | 还清了 `pin`/`ekey` 两个 Keychain 副本 | ✅ 完整 |

## 2. 顺带核了那 4 处仍写着 `hasPrefix("2118")` 的地方

ROUND-145 把「永久」判据统一到 `expiryDate` 后，还剩 4 处。逐个判定：

| 位置 | 性质 | 判定 |
|---|---|---|
| `CredentialOrgState:9` | **`expiryDate` 自身** | ✅ 口径来源 |
| `CredentialOrg:548/549`（`expiryLabel`） | **文案层唯一一处** | ✅ 注释写明"这条判据此前在 4 处界面各有一份，**收成一处**" |
| `MobileKeyService:202` | 手机钥匙域 | ✅ `k.forever` 是权威字段，`hasPrefix` 只是兜底 |

注意 `expiryLabel` 那一处的注释质量：它不只是说"这么做"，还写明了**为什么必须这么做**
（"直接印出来就是把内部哨兵当事实报给用户"）**以及它的历史**（原来散在 4 处）。
这是本仓注释的正面样板。

## 3. 方法论

**"清理函数"这条判据，本轮的三次核对都落在"查引用表"上。**

具体的查法：

```
grep "<实体字段名>"      # 例如 dongle.mac / gateway.mac / memberID
```

| 实体 | 引用它的表 |
| 
| 成员 | `owner`（台账）/ `memberID`（手机钥匙）/ `whoId`（认领映射）/ `kf_duty_week` |
| 设备 | 14+ 族 `kf_*_<mac>` + 3 族钥匙串副本 |
| **Dongle / Gateway** | **无**（自包含） |
| 手机钥匙 | 无（自身是叶子） |

**判据**：删一个实体前，先列出"哪些表有指向它的字段" —— 这比"看清理函数里写了什么"可靠，
因为后者只能发现"写了的"，发现不了"漏写的"。

## 4. 本轮没有代码改动

三条路径都正确。按 objective 的「无可分析时不要强行硬分析」，不硬找改动。
（这条也是 `AUDIT-METHOD.md §6` 的实践：**"审过没问题"是结果，要记录。**）
