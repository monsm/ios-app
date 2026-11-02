# AUDIT-ROUND-322 · 第 322 轮：字典写入的守卫，只装在出过事的那一个上

> CI：`8ff51157` build 全绿（errors=0）。

## 1. 方法：把「读-改-写」与「守卫」求差

| 集合 | 数量 |
|---|---|
| `var map = getDict(k)` 形式的读-改-写 | **10** |
| 其中带 `isDictCorrupt` 守卫的 | **1**（`saveKeychain`，上一轮刚补） |

## 2. 无守卫的 9 个（本轮全部补上）

| 族 | 写入点 | 损坏时一次保存的后果 |
|---|---|---|
| `kf_members` | `addMember` `renameMember` `setMemberInfo` `removeMember` | **所有成员消失** |
| `kf_keychain_dongles` | `saveDongle` `removeDongle` | 所有硬件钥匙串记录消失 |
| `kf_gateways` | `saveGateway` `removeGateway` | 所有网关消失 |
| `kf_keychains` | `removeKeychain` | **删一把锁 → 其它锁全部消失** |

（`getDict` 在解码失败时返回 `[:]` ⇒ 写回的是「只剩本次操作那一项」的空表。）

## 3. 修法：把判据收成一处

    func canWriteDict(_ k: String) -> Bool {
        guard isDictCorrupt(k) else { return true }
        BleTelemetry.recordEvent("字典不可解，写入被拒：" + k, ok: false)
        return false
    }

之后每个写入点一行：`guard store.canWriteDict("kf_X") else { return }`。
收成一处的意义：**下一个人加新的字典写入点时，只要走这个入口就不会再漏**（而不是再记一遍该查什么）。

（`addMember` 返回 `Member?`，那一处是 `return nil` —— 这轮差点写成 `return`，属于「批量替换时要逐个看签名」。）

## 4. 为什么只在其中一个上

上一轮的 `saveKeychain` 之所以修，是因为**它出过事**（注释里还留着那次事故的描述）；
同一族里没出过事的 9 个，就没人想起来。

## 5. 方法论

**「同类结构的 N 个写入点」几乎总是一个有守卫、其余没有 —— 因为守卫是被某次事故教会后只装在了原地。**

| 修完一处后的动作 | 结果 |
|---|---|
| 就地修好，收工 | 其余 N-1 个继续裸奔（本轮之前的状态） |
| **grep 同构写法，全部补齐 + 收成统一入口** | 这类缺陷在结构上不再可能发生 ✅ |

判据：**修一个「守卫缺失」时，先 grep 这个守卫的**同构写法**（同一个 `getDict` / 同一个 `save`），把 N 找出来 —— 而不是只修眼前这一个。**
