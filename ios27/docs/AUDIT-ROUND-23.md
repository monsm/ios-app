# AUDIT-ROUND-23 · 第二十三轮：写路径读的是"展示层过滤后的数据"

> CI：`885371c` 已验证编译通过（errors=0、build_ok=1）；本轮提交待回执

## 1. 缺陷：空壳里写一次，把整段回收站/版本历史覆盖掉

`CredBinStore.all(mac)` 的第一行是：

    if DB.isDecoy { return [] }     // SEC-03：空壳不列回收站

这是**展示层**语义（别让胁迫者看到条目）。
但写路径也用了它：

    static func addPwds(...) {
        var items = all(mac)        // ← 空壳里拿到 []
        items.append(新条目)
        DB.store.setCodable(key(mac), items)   // ← 整表覆盖成只剩这一条
    }

所以：**空壳模式下发生任何一次删除级联，回收站里原有的全部条目会被静默抹掉。**
同一形状也在 `CredHistoryStore.capture`：空壳里拍一次快照，整段版本历史只剩这一份。

`clear()` 另有反向问题：空壳里 `all()` 返回空 ⇒ 遍历不到条目 ⇒
Keychain 里的口令副本**不会被清**，而键被删掉 —— 留下孤儿密钥。

## 2. 修法

- 两个 Store 各加 `private static func stored(_:)`：**读原始存储**、不判空壳、不排序；
- 所有写路径（addPwds / addFps / restore / purge / clear / capture）改用 `stored()`；
- 空壳过滤只保留在 `all()`（展示层）。

## 3. 顺带补上回收站的保留上限

`CredHistoryStore.capture` 一直有「只留 10 份，被裁掉的快照连 Keychain 副本一起清」；
**回收站没有**。于是 plist 数组与密钥副本一起无限堆积。
现在统一收口到 `commit(mac:items:)`：裁到 `maxItems = 100`，
并把被裁条目的 Keychain 副本一并删除。

## 4. 防复发：privacy 闸门第 14 条

写函数（addPwds/addFps/restore/purge/clear/capture）体内不许出现 `all(mac)`。
已验证抓得住：把 `addPwds` 改回 `all(mac)`，闸门立刻红：

```
privacy: FAIL — 1 处回归
  Features/Keys/CredentialStudioStores.swift:70 — addPwds 用 all(mac) 读存储：
    空壳下会返回空并把历史覆盖掉 → 改用 stored(mac) 读原始存储
```

## 5. 新增测试

- `testBinWriteDoesNotWipeHistoryInDecoyMode`：空壳下写一条，确认既有条目仍在（2 条）；
- `testBinHasRetentionCap`：回收站必须有上限且不过大。

## 6. 方法论

**同一个函数被读和写两用，就会出现"过滤语义泄漏进存储层"。**
`all()` 的名字与注释都在讲"展示"，但它的调用者里有写路径 —— 这类错误读代码时极难发现，
因为每一处都很合理，只有把「谁在读、读来干什么」摆在一起才看得见。

可复用的判据：**任何带"过滤/权限/模式"判断的读取函数，都不该出现在写路径里。**
