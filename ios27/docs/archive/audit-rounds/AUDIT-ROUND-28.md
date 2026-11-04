# AUDIT-ROUND-28 · 第二十八轮：同一族的第二处 —— 记录页覆盖层

> CI：`49ee557` 已验证（errors=0、build_ok=1）；`af30ed5` / `eea6ef1` 及本轮提交待回执

## 1. 上一轮修的是「一个实例」，这轮找到「同一族的下一个」

第 23 轮修了 `CredentialStudioStores`：写路径误用了空壳过滤后的 `all()`。
本轮按同一形状扫 `RecordOverlay`（记录页的备注 / 旗标 / 处置覆盖层），发现完全一样的缺陷：

```
static func notes(_ mac: String) -> [String: String] {
    if DB.isDecoy { return [:] }        // 展示层语义
    return DB.store.get(...) ?? [:]
}
static func setNote(...) {
    var m = notes(mac)                  // 空壳里拿到 [:]
    ... ; DB.store.setCodable(noteKey(mac), m)   // 整表被覆盖
}
```

`toggleFlag`（读 `flags`）与 `setDisposition`（读 `dispositions`）同样。

## 2. 顺带发现一处不一致

三族里只有 `notes()` 判空壳：

| 读取器 | 空壳过滤 |
|---|---|
| `notes()` | 有 |
| `flags()` | **无** |
| `dispositions()` | **无** |

旗标与处置同样按行键存在，同样泄露「这条记录存在且被标记过」。同一份数据两种待遇，
说明当初只按「想到哪写到哪」补的。

## 3. 修法

- 新增 `rawNotes` / `rawFlags` / `rawDispositions`（读原始存储）；
- 写路径（`setNote` / `toggleFlag` / `setDisposition`）改用 raw 版本；
- 展示读取器统一加空壳过滤，三族同口径。

## 4. 防复发：privacy 闸门第 16 条

`RecordSearch.swift` 的三个写函数体内不许出现 `notes(mac)` / `flags(mac)` / `dispositions(mac)`。已验证：

```
privacy: FAIL — 1 处回归
  Engine/RecordSearch.swift:52 — setNote 用展示层读取器（空壳下返回空会把整表覆盖）
    → 改用 rawNotes/rawFlags/rawDispositions
```

## 5. 新增测试

- `testRecordOverlayIsDecoyConsistent`：空壳下三族都必须为空；
- `testOverlayWriteInDecoyDoesNotWipeTable`：空壳里写一条，旧备注必须仍在。

## 6. 方法论

**修完一个实例后，应该立刻搜「同样形状」还有几处。**
第 23 轮我只改了 `CredentialStudioStores`，当时没做这一步；这一轮的 `RecordOverlay` 本来可以在上一轮一起修掉。

可复用做法：修完写路径/读路径混用这类问题后，**全局搜 `if DB.isDecoy` 的每一个读取器，逐个检查它的调用方里有没有写路径**。
