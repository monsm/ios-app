# AUDIT-ROUND-52 · 第五十二轮：我的备份修复本来是无效的（导出文本由 canonical 生成）

> CI：`7f87aef` 已验证；`2971b60` 仍未回执。本轮本地提交，不推送。

## 1. 自查上一轮的备份修复，发现它什么都不做

`BackupCatalog`/`BackupStudioKit` 的导出路径是：

```
exportText(b) = canonical(b) 去掉右括号 + ,"checksum":"<fnv>" + }
```

也就是说 **导出的 JSON 文本完全由 `BackupCanonical.canonical(_:)` 逐字段构造**，
不是 `JSONEncoder` 编出来的。

而 `canonical` 里的 `canonGlobals` / `metaValue` 是**显式白名单**：没列出的字段**不会出现在导出文本里**。

所以我上一轮只给 `BackupBundle.Globals` 加了 `memberExt` 字段 —— **导出文本里根本不会有它**，
恢复端自然读不到。功能等于没做，而且**不会报错**（校验和两边都用同一份 canonical，永远对得上）。

这正是该文件第 171 行自己写的警告：

> 「字段存在但这里不序列化 ⇒ 导出文本里没有它 ⇒ 换机全丢」

## 2. 本轮补上（两处）

1. `metaValue`：新增 `alerts` 段（`pwd:<alias>` 排序，内层 day/d3/d1/h24/h2 固定序）；
2. `canonGlobals`：新增 `memberExt` 段（成员 id 排序，12 个字段按字母序 emit）；
   顶层位置在 `keychainDongles` 与 `passcode` 之间（保持字母序）。

两段都是"缺字段就不 emit"，因此**旧包（没有这两段）的 canonical 与校验和不变**，向后兼容。

## 3. 方法论

**一个数据字段要真正"进备份"，必须同时改三处：结构体、canonical、恢复端。**
只改结构体是最危险的一种 —— 编译通过、类型正确、运行不报错，**数据就是不会出现**。

判据：**任何"新增备份字段"的改动，都要同时搜 `BackupCanonical.swift` 里有没有对应 emit**。
搜不到就是没做。
