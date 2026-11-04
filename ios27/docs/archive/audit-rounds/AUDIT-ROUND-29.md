# AUDIT-ROUND-29 · 第二十九轮：按自己写的判据做全局扫描，又抓两处

> CI：`af30ed5` 已验证（errors=0、build_ok=1）；`eea6ef1` / `98da7ed` / 本轮提交待回执

## 1. 这轮把上轮那条判据真的执行了一遍

上轮我写下的做法是：**全局搜 `if DB.isDecoy` 的每一个读取器，逐个检查调用方里有没有写路径**。
本轮照做，14 处全部过了一遍。结果：

| 读取器 | 写路径是否误用 |
|---|---|
| `ledger()` | 否 —— `saveLedger` 在空壳**拒写**（N-01 守卫），所以基于它的写入是 no-op |
| `keychains()` / `keychain()` / `dongles()` / `gateways()` / `members()` | 否（无写路径调用） |
| `readLogs()` | 否（写路径用 `get(...)` 原始读） |
| `CredBinStore.all` / `CredHistoryStore.all` | 否（第 23 轮已修） |
| `RecordOverlay.notes/flags/dispositions` | 否（第 28 轮已修） |
| **`MobileKeyService.list()`** | **是 —— 本轮修复** |

## 2. 缺陷：`issue` / `revoke` 在空壳里会整批覆盖手机钥匙

```swift
// issue
let used = list(kc.mac)                 // 空壳 → []
...
save(kc.mac, used + [key])              // → 只剩新的一条

// revoke
save(kc.mac, list(kc.mac).filter { ... })   // 空壳 → 空表
```

两个后果：

- **发放**：空壳里发一把钥匙，会把此前所有手机钥匙从本机记录里抹掉（锁上那些 ekey 仍然有效，
  但本机再也列不出来、也撤销不了 —— 等于失去对它们的管辖）；
- **撤销**：空壳里撤销一把，会把整张表清空（同样，锁上其它钥匙还活着）。

另外 `availablePin(used:)` 也会因为 `used` 为空而**挑到已被占用的 pin**
（同一 pin 签两把钥匙），属于同一处根因的副作用。

## 3. 修法

加 `rawList(_:)`（读原始存储、回填 Keychain 秘密），`issue` / `revoke` 改用它；
`list()` 保持空壳过滤，只给展示层。

## 4. 防复发：privacy 闸门第 17 条

`issue` / `revoke` 函数体内不许出现 `list(kc.mac)` / `list(mac)`。已验证：

```
privacy: FAIL — 1 处回归
  Engine/MobileKeyService.swift:134 — issue 用 list() 读存储：空壳下返回空会把整批手机钥匙覆盖
    → 改用 rawList()
```

## 5. 新增测试

`testMobileKeyRawListSurvivesDecoy`：空壳下 `list()` 为空、`rawList()` 仍能读到真实记录。

## 6. 方法论

**一条判据只有在真的被执行过一次之后才算判据。**
上轮写下"全局搜 `if DB.isDecoy`"时，我只修了眼前那一个；这轮执行后才发现第三处、第四处。
而且这次扫描把"为什么台账族安全"也讲清楚了 —— `saveLedger` 的拒写守卫，
那是第 2 轮就加的，正好挡住了这一族。
