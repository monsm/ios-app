# AUDIT-ROUND-230 · 第 230 轮：删成员漏清「借用登记」

> CI：**`3b231a8` build 全绿**（`project=yes / swift_files=150`）—— 提前失效清理编译通过。

## 1. 缺陷

`MemberOpsStore.setBorrow(mac, memberID:…)` 的存储是：

```swift
var map = borrows(mac)
map[memberID] = MemberBorrow(by: by, due: due, at: …)
DB.store.setCodable("kf_mborrow_" + mac, map)    // 键 = memberID
```

而 `DB.removeMember` 清了台账归属 / 认领映射 / 档案扩展 / 值班周表 / 手机钥匙，
**唯独没清 `kf_mborrow_<mac>`**。

| 结果 | 说明 |
|---|---|
| 借用列表里出现「借用人：<已删除的 id>」 | 界面拿不到成员名，只能显示原始 id |
| 该条目永远占着 | 没有 UI 能删它（成员已不存在） |

## 2. 修法

与同文件里手机钥匙那段同款（遍历**存储键**而不是 `keychains()`，钥匙串被删但键还在时也能清）：

```swift
for key in store.keys() where key.hasPrefix("kf_mborrow_") {
    var map = store.get([String: MemberBorrow].self, key) ?? [:]
    if map.removeValue(forKey: id) != nil { store.setCodable(key, map) }
}
```

（`store.keys()` 返回的是新数组，循环里改 `store` 安全。）

## 3. 本轮另外 3 项「审过、正确」

| 检查 | 结论 |
|---|---|
| `kf_offboard_<member>` 是否也需要清 | **不需要** —— 全仓只有两处注释提到它，**零读零写**，是死键 |
| `MemberBorrow.by` 存的是名字还是 id | 名字（`by: String`），所以孤儿条目影响仅限于显示 |
| `Ledger` 结构 | 只有 `pwds`/`fps` ⇒ `CredHistoryStore.restore` 用 `Ledger()` 重建不丢字段 |

## 4. 方法论

**删成员这条链，是"派生数据排查清单"最好的练手场 —— 它挂了 6 种外部状态。**

| 派生数据 | 清了吗 |
|---|---|
| 台账 owner | ✅ |
| 认领映射 `kf_mclaim_` | ✅ |
| 档案扩展 / 徽章 / 生日 | ✅ |
| 值班周表 `kf_duty_week` | ✅ |
| 手机钥匙 `kf_mkey_` | ✅（2026-11-01 补） |
| **借用登记 `kf_mborrow_`** | ✅ **本轮补** |

判据：**每加一个"以成员 id 为键"的存储，就回头把它加进 `removeMember` 的清理清单。**
这条清单已经补过三次了 —— 说明它不是"一次想全"的事，而是每次新增都要回头加一行。
