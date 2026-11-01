# AUDIT-ROUND-221 · 第 221 轮：**CI 又红了**（引用了模型上不存在的字段），并做成闸门

> CI：`f3ae3f7` **build_ok=0** —— `MobileKeyScreen.swift:52` 引用了 `StatusSnapshotData` 上不存在的 `pinInfoBinding`。

## 1. 红的是什么

我上一轮接 `foreignKeyHint` 时写了：

```swift
app.lastStatus?.status.pinInfoBinding
```

而 `StatusSnapshotData` 只持久化了 `pinStock`，**没有** `pinInfoBinding` ——
字段解析出来了（`LockStatus.pinInfoBinding`），但没进快照模型。

## 2. 修复

给 `StatusSnapshotData` 补上这个字段，与 `pinCap/pwdCap/fpCap` 同口径（Optional，旧快照缺键解码为 nil）：

| 位置 | 改动 |
|---|---|
| 属性 | `var pinInfoBinding: Int?` |
| `CodingKeys` | 加 `pinInfoBinding` |
| 成员初始化器 | 加参数 + 赋值 |
| 容错解码 | `decodeIfPresent` |
| `writeStatus` 映射 | `st.pinInfoBinding > 0 ? … : nil` |

## 3. 这是同一个坑的第二次

| 次数 | 错误 | 本地闸门能否发现 |
|---|---|---|
| 第 1 次（Round 197） | 扩展里声明存储属性 | ❌ 当时不能 → 已加闸门 |
| **第 2 次（本轮）** | **引用模型上不存在的字段** | ❌ 当时不能 → **本轮加闸门** |

**同一个坑踩两次，就不是「不小心」，而是缺一道检查。**

### 新闸门

`swiftcheck` 现在会：解析 `StatusSnapshotData` 的字段表 → 扫描全仓 `lastStatus?.status.X` → X 不在字段表里就红。

双向验证：把 `pinInfoBinding` 改成 `pinInfoBindin` ⇒ 立刻红并指出文件名；恢复后 22/22 绿。

## 4. 方法论

**「加字段」是一个跨文件的动作，而这个仓把它拆成了 5 处**（属性 / CodingKeys / init / decode / writeStatus）。
少任何一处都只是「运行时读到 nil」，**唯独「少属性本身」会编译失败** —— 而那正是最容易漏的，
因为读代码时看到 `LockStatus.pinInfoBinding` 就会以为整条链都有。

判据：**给持久化模型加字段时，先问「这个值从哪来、往哪去」，把 5 处一次写完；闸门兜住「根本不存在的字段」。**
